const kernel = @import("../../main.zig");
const std = @import("std");

pub const MAX_UNIX_PATH: usize = 108;
pub const MAX_BACKLOG: usize = 16;
const SOCK_BUFFER_SIZE = 4096;

const sockaddr_un = extern struct {
    sun_family: u16,
    sun_path: [MAX_UNIX_PATH]u8,
};

const MAX_BOUND_SOCKETS: usize = 32;
var bound_sockets: [MAX_BOUND_SOCKETS]?*UnixSocket = @splat(null);

fn registerBound(sock: *UnixSocket) bool {
    for (&bound_sockets) |*slot| {
        if (slot.* == null) {
            slot.* = sock;
            return true;
        }
    }
    return false;
}

fn unregisterBound(sock: *UnixSocket) void {
    for (&bound_sockets) |*slot| {
        if (slot.* == sock) {
            slot.* = null;
            return;
        }
    }
}

// Length of the AF_UNIX name inside sun_path. An abstract socket has
// sun_path[0] == 0 and its name (including that leading NUL) runs for the
// full addr_len, so it must NOT be treated as a C string. A pathname socket
// is NUL-terminated. libxcb connects to the abstract name first, so getting
// this right is what lets X clients reach the server.
fn unixNameLen(sun_path: []const u8) usize {
    if (sun_path.len == 0)
        return 0;
    if (sun_path[0] == 0)
        return sun_path.len;
    var n: usize = 0;
    while (n < sun_path.len and sun_path[n] != 0) : (n += 1) {}
    return n;
}

pub fn findBoundSocket(path: []const u8) ?*UnixSocket {
    for (bound_sockets) |slot| {
        if (slot) |sock| {
            if (sock.bound_path_len > 0 and
                sock.bound_path_len == path.len and
                std.mem.eql(u8, sock.bound_path[0..sock.bound_path_len], path))
            {
                return sock;
            }
        }
    }
    return null;
}


const UnixSocket = struct {
    sock: kernel.socket.Socket = undefined,

    _buffer: [SOCK_BUFFER_SIZE]u8,
    rb: kernel.ringbuf.RingBuf,
    conn: ?*kernel.socket.Socket,
    bound_path: [MAX_UNIX_PATH]u8 = @splat(0),
    bound_path_len: usize = 0,

    is_listening: bool = false,
    accept_queue: kernel.list.ListHead = kernel.list.ListHead.init(),
    accept_count: usize = 0,
    accept_backlog: usize = MAX_BACKLOG,
    accept_wait: kernel.wq.WaitQueueHead = kernel.wq.WaitQueueHead.init(),
    pending_link: kernel.list.ListHead = kernel.list.ListHead.init(),

    inline fn parent(base: *kernel.socket.Socket) *UnixSocket {
        return @fieldParentPtr("sock", base);
    }

    fn setup(self: *UnixSocket) void {
        self._buffer = @splat(0);
        self.rb = kernel.ringbuf.RingBuf._init(self._buffer[0..SOCK_BUFFER_SIZE]) catch {
            @panic("Make buffer size a power of two.");
        };
        self.conn = null;
        self.is_listening = false;
        self.bound_path = @splat(0);
        self.bound_path_len = 0;
        self.accept_queue.setup();
        self.accept_count = 0;
        self.accept_backlog = MAX_BACKLOG;
        self.accept_wait.setup();
        self.pending_link.setup();
    }

    fn getName(
        base: *kernel.socket.Socket,
        addr: *kernel.socket.sockaddr,
        peer: bool,
    ) !usize {
        var socket: *UnixSocket = UnixSocket.parent(base);
        if (peer) {
            if (socket.conn) |peer_conn| {
                socket = UnixSocket.parent(peer_conn);
            } else {
                return kernel.errors.PosixError.ENOTCONN;
            }
        }
        socket.sock.lock.lock();
        defer socket.sock.lock.unlock();

        addr.sa_family = kernel.socket.AF_UNIX;
        var addr_un = @as(*sockaddr_un, @ptrCast(addr));
        var len: u32 = 0;
        if (socket.bound_path_len > 0) {
            @memcpy(
                addr_un.sun_path[0..socket.bound_path_len],
                socket.bound_path[0..socket.bound_path_len]
            );
            len = @intCast(@sizeOf(u16) + socket.bound_path_len + 1);
        } else {
            addr_un.sun_path[0] = 0;
            len = @sizeOf(u16) + 1;
        }
        return len;
    }

    fn bind(
        base: *kernel.socket.Socket,
        addr_ptr: *anyopaque,
        addr_len: u32
    ) !void {
        if (addr_len < 3 or addr_len > @sizeOf(sockaddr_un)) {
            return kernel.errors.PosixError.EINVAL;
        }
        const addr: *const sockaddr_un = @ptrCast(@alignCast(addr_ptr));

        const path_max = addr_len - @offsetOf(sockaddr_un, "sun_path");
        const path_len = unixNameLen(addr.sun_path[0..path_max]);

        if (findBoundSocket(addr.sun_path[0..path_len]) != null)
            return kernel.errors.PosixError.EADDRINUSE;

        const unix_sock: *UnixSocket = UnixSocket.parent(base);
        base.lock.lock();
        @memcpy(unix_sock.bound_path[0..path_len], addr.sun_path[0..path_len]);
        unix_sock.bound_path_len = path_len;
        base.lock.unlock();

        if (!registerBound(unix_sock)) {
            base.lock.lock();
            unix_sock.bound_path_len = 0;
            base.lock.unlock();
            return kernel.errors.PosixError.ENOMEM;
        }
    }

    fn listen(
        base: *kernel.socket.Socket,
        backlog: u32
    ) !void {
        const sock: *UnixSocket = UnixSocket.parent(base);
        if (sock.bound_path_len == 0) {
            return kernel.errors.PosixError.EINVAL;
        }

        base.lock.lock();
        sock.is_listening = true;
        sock.accept_backlog = if (backlog > 0 and backlog <= MAX_BACKLOG) backlog else MAX_BACKLOG;
        base.lock.unlock();
    }

    fn accept(
        base: *kernel.socket.Socket
    ) !u32 {
        const listener: *UnixSocket = UnixSocket.parent(base);
        if (!listener.is_listening) {
            return kernel.errors.PosixError.EINVAL;
        }

        while (true) {
            base.lock.lock();
            if (!listener.accept_queue.isEmpty()) {
                const pending_node = listener.accept_queue.next.?;
                pending_node.del();
                pending_node.setup();
                listener.accept_count -|= 1;
                base.lock.unlock();

                const un_client_sock = pending_node.entry(
                    UnixSocket, "pending_link"
                );

                const server_sock = try unix_family.create(
                    listener.sock.socket_type,
                    listener.sock.protocol
                );
                const un_server_sock: *UnixSocket = UnixSocket.parent(server_sock);
                // TODO: do family.release
                // errdefer kernel.mm.kfree(server_sock);

                const new_fd = try kernel.socket.sockAllocFd(server_sock, 0);

                un_client_sock.conn = server_sock;
                un_server_sock.conn = &un_client_sock.sock;

                return @intCast(new_fd);
            }
            base.lock.unlock();

            // TODO: Make socket know that its nonblock or not (*to File)
            // if (file.flags & kernel.fs.file.O_NONBLOCK != 0)
            //     return kernel.errors.PosixError.EAGAIN;
            listener.accept_wait.wait(true, 0);
            if (kernel.task.current().hasPendingSignal())
                return kernel.errors.PosixError.ERESTARTSYS;
        }
    }

    fn connect(
        base: *kernel.socket.Socket,
        addr_ptr: *anyopaque,
        addr_len: u32
    ) !void {
        const sock = UnixSocket.parent(base);
        if (sock.conn != null) {
            return kernel.errors.PosixError.EISCONN;
        }

        const addr: *const sockaddr_un = @ptrCast(@alignCast(addr_ptr));
        if (addr.sun_family != kernel.socket.AF_UNIX and addr.sun_family != kernel.socket.AF_LOCAL) {
            return kernel.errors.PosixError.EAFNOSUPPORT;
        }

        if (addr_len < 3 or addr_len > @sizeOf(sockaddr_un)) {
            return kernel.errors.PosixError.EINVAL;
        }

        const path_max = addr_len - @offsetOf(sockaddr_un, "sun_path");
        const path_len = unixNameLen(addr.sun_path[0..path_max]);

        const listener = findBoundSocket(addr.sun_path[0..path_len]) orelse
            return kernel.errors.PosixError.ECONNREFUSED;

        if (!listener.is_listening) {
            return kernel.errors.PosixError.ECONNREFUSED;
        }

        listener.sock.lock.lock();
        if (listener.accept_count >= listener.accept_backlog) {
            listener.sock.lock.unlock();
            return kernel.errors.PosixError.ECONNREFUSED;
        }
        sock.pending_link.setup();
        listener.accept_queue.addTail(&sock.pending_link);
        listener.accept_count += 1;
        listener.sock.lock.unlock();

        listener.accept_wait.wakeUpOne();

        while (sock.conn == null) {
            // TODO: NONBLOCK
            // if (file.flags & kernel.fs.file.O_NONBLOCK != 0)
            //     return kernel.errors.PosixError.EAGAIN;

            kernel.task.current().wakeup_time = kernel.currentMs() + 10;
            kernel.task.current().state = .INTERRUPTIBLE_SLEEP;
            kernel.sched.reschedule();
            if (kernel.task.current().hasPendingSignal())
                return kernel.errors.PosixError.ERESTARTSYS;
        }
    }

    fn recvfrom(
        base: *kernel.socket.Socket,
        buf: [*]u8,
        size: usize
    ) !usize {
        const un_sock = UnixSocket.parent(base);
        base.lock.lock();
        defer base.lock.unlock();

        while (un_sock.rb.isEmpty()) {
            if (un_sock.conn == null) {
                return kernel.errors.PosixError.ENOTCONN;
            }
            // TODO: NONBLOCK
            // if (base.flags & kernel.fs.file.O_NONBLOCK != 0)
            //     return kernel.errors.PosixError.EAGAIN;

            var wq_node = kernel.wq.WaitQueueNode.init(kernel.task.current());
            wq_node.setup();

            base.rw_queue.addToQueue(&wq_node);
            base.lock.unlock();
            base.rw_queue.waitIfInQueue(&wq_node, true, 0);

            if (kernel.task.current().hasPendingSignal()) {
                base.lock.lock();
                return kernel.errors.PosixError.ERESTARTSYS;
            }

            base.lock.lock();
        }
        const ret_size: usize = un_sock.rb.readInto(buf[0..size]);
        if (un_sock.conn) |remote| {
            remote.rw_queue.wakeUpOne();
        }
        return ret_size;
    }

    fn sendto(
        base: *kernel.socket.Socket,
        buf: [*]const u8,
        size: usize
    ) !usize {
        const un_sock: *UnixSocket = UnixSocket.parent(base);
        var remote = un_sock.conn orelse
            return kernel.errors.PosixError.ENOTCONN;
        const un_remote: *UnixSocket = UnixSocket.parent(remote);

        remote.lock.lock();
        defer remote.lock.unlock();
        while (un_remote.rb.isFull()) {
            // TODO: NONBLOCK
            // if (base.flags & kernel.fs.file.O_NONBLOCK != 0)
            //     return kernel.errors.PosixError.EAGAIN;

            var wq_node = kernel.wq.WaitQueueNode.init(kernel.task.current());
            wq_node.setup();

            base.rw_queue.addToQueue(&wq_node);
            remote.lock.unlock();
            base.rw_queue.waitIfInQueue(&wq_node, true, 0);
            if (kernel.task.current().hasPendingSignal()) {
                remote.lock.lock();
                return kernel.errors.PosixError.ERESTARTSYS;
            }

            if (un_sock.conn == null) {
                remote.lock.lock();
                return kernel.errors.PosixError.ENOTCONN;
            }

            remote.lock.lock();
        }
        defer remote.rw_queue.wakeUpOne();
        for (buf[0..size], 0..) |ch, idx| {
            if (!un_remote.rb.push(ch))
                return idx;
        }
        return size;
    }

    fn poll(
        base: *kernel.socket.Socket,
        pollfd: *kernel.poll.PollFd,
        poll_table: ?*kernel.poll.PollTable
    ) !usize {
        var ready: u32 = 0;
        const un_sock: *UnixSocket = UnixSocket.parent(base);

        if (un_sock.is_listening) {
            if (pollfd.events & kernel.poll.POLLIN != 0) {
                base.lock.lock();
                const has_pending = !un_sock.accept_queue.isEmpty();
                base.lock.unlock();
                if (has_pending) {
                    pollfd.revents |= kernel.poll.POLLIN;
                    ready = 1;
                }
            }
            if (ready == 0 and pollfd.events & kernel.poll.POLLIN != 0) {
                if (poll_table) |pt|
                    try pt.addNode(&un_sock.accept_wait);
            }
            return ready;
        }

        if (pollfd.events & kernel.poll.POLLIN != 0) {
            base.lock.lock();
            const avail = un_sock.rb.available();
            base.lock.unlock();
            if (avail > 0) {
                pollfd.revents |= kernel.poll.POLLIN;
                ready = 1;
            }
        }
        if (pollfd.events & kernel.poll.POLLOUT != 0) {
            if (un_sock.conn) |remote| {
                const un_remote: *UnixSocket = UnixSocket.parent(remote);
                if (!un_remote.rb.isFull()) {
                    pollfd.revents |= kernel.poll.POLLOUT;
                    ready = 1;
                }
            }
        }
        if (
            ready == 0
            and pollfd.events & (kernel.poll.POLLIN | kernel.poll.POLLOUT) != 0
        ) {
            if (poll_table) |pt|
                try pt.addNode(&base.rw_queue);
        }
        return ready;
    }

    fn socketpair(
        base_a: *kernel.socket.Socket,
        base_b: *kernel.socket.Socket,
    ) !void {
        UnixSocket.parent(base_a).conn = base_b;
        UnixSocket.parent(base_b).conn = base_a;
    }

    fn unix_ioctl(
        socket: *kernel.socket.Socket,
        op: u32,
        data: usize
    ) !u32 {
        _ = socket;
        _ = op;
        _ = data;
        return kernel.errors.PosixError.ENOTTY;
    }
};

const unix_family = kernel.socket.ProtocolFamily {
    .create = unix_create,
};

const unix_protocol_ops = kernel.socket.ProtocolOps{
    .ioctl      = UnixSocket.unix_ioctl,
    .getName    = UnixSocket.getName,
    .bind       = UnixSocket.bind,
    .listen     = UnixSocket.listen,
    .accept     = UnixSocket.accept,
    .connect    = UnixSocket.connect,
    .recvfrom   = UnixSocket.recvfrom,
    .sendto     = UnixSocket.sendto,
    .poll       = UnixSocket.poll,
    .socketpair = UnixSocket.socketpair,
};

pub const IPv4Socket = struct {
    sock: kernel.socket.Socket,
};

fn unix_create(socket_type: u16, protocol: u8) !*kernel.socket.Socket {
    const socket = kernel.mm.kmalloc(UnixSocket) orelse
        return kernel.errors.PosixError.ENOMEM;
    socket.sock.setup(kernel.socket.AF_UNIX, socket_type, protocol);
    socket.setup();
    socket.sock.ops = &unix_protocol_ops;
    return &socket.sock;
}

pub fn init() void {
    kernel.socket.net_families[kernel.socket.AF_UNIX] = &unix_family;
}
