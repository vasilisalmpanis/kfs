const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const AF_UNIX: u16 = 1;
pub const AF_LOCAL: u16 = AF_UNIX;

pub const SOCK_STREAM: u16 = 1;
pub const SOCK_DGRAM: u16 = 2;

pub const MAX_UNIX_PATH: usize = 108;
pub const MAX_BACKLOG: usize = 16;
const SOCK_BUFFER_SIZE = 4096;

pub const sockaddr_un = extern struct {
    sun_family: u16,
    sun_path: [MAX_UNIX_PATH]u8,
};

pub const sockaddr = extern struct {
    sa_family: u16,
    sa_data: [14]u8,
};


pub const Socket = struct {
    _buffer: [SOCK_BUFFER_SIZE]u8,
    rb: krn.ringbuf.RingBuf,
    conn: ?*Socket,
    list: lst.ListHead,
    lock: krn.Spinlock = krn.Spinlock.init(),

    sock_type: u16 = SOCK_STREAM,
    is_listening: bool = false,
    bound_path: [MAX_UNIX_PATH]u8 = .{0} ** MAX_UNIX_PATH,
    bound_path_len: usize = 0,

    accept_queue: lst.ListHead = lst.ListHead.init(),
    accept_count: usize = 0,
    accept_backlog: usize = MAX_BACKLOG,
    accept_wait: krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),

    rw_queue: krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),

    pending_link: lst.ListHead = lst.ListHead.init(),

    pub fn setup(self: *Socket) void {
        self._buffer = .{0} ** SOCK_BUFFER_SIZE;
        self.rb = krn.ringbuf.RingBuf._init(self._buffer[0..SOCK_BUFFER_SIZE]) catch {
            @panic("Make buffer size a power of two.");
        };
        self.conn = null;
        self.list.next = &self.list;
        self.list.prev = &self.list;
        self.lock = krn.Spinlock.init();
        self.sock_type = SOCK_STREAM;
        self.is_listening = false;
        self.bound_path = .{0} ** MAX_UNIX_PATH;
        self.bound_path_len = 0;
        self.accept_queue.setup();
        self.accept_count = 0;
        self.accept_backlog = MAX_BACKLOG;
        self.accept_wait.setup();
        self.pending_link.setup();
        self.rw_queue.setup();
    }

    pub fn delete(self: *Socket) void {
        self.lock.lock();
        if (self.conn) |remote| {
            remote.lock.lock();
            remote.conn = null;
            remote.lock.unlock();
            remote.rw_queue.wakeUpOne();
        }
        if (self.is_listening) {
            unregisterBound(self);
        }
        self.lock.unlock();
        krn.mm.kfree(self);
    }

    pub fn newSocket() ?*Socket {
        const sock: ?*Socket = krn.mm.kmalloc(Socket);
        if (sock) |_sock| {
            _sock.setup();
        }
        return sock;
    }
};

const MAX_BOUND_SOCKETS: usize = 32;
var bound_sockets: [MAX_BOUND_SOCKETS]?*Socket = .{null} ** MAX_BOUND_SOCKETS;

fn registerBound(sock: *Socket) bool {
    for (&bound_sockets) |*slot| {
        if (slot.* == null) {
            slot.* = sock;
            return true;
        }
    }
    return false;
}

fn unregisterBound(sock: *Socket) void {
    for (&bound_sockets) |*slot| {
        if (slot.* == sock) {
            slot.* = null;
            return;
        }
    }
}

pub fn findBoundSocket(path: []const u8) ?*Socket {
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

pub fn do_socket(family: u32, sock_type: u32, protocol: u32) !u32 {
    _ = protocol;
    if (family != AF_UNIX and family != AF_LOCAL) {
        return krn.errors.PosixError.EAFNOSUPPORT;
    }
    if (sock_type != SOCK_STREAM) {
        return krn.errors.PosixError.ESOCKTNOSUPPORT;
    }

    const sock = Socket.newSocket() orelse return krn.errors.PosixError.ENOMEM;
    errdefer krn.mm.kfree(sock);
    sock.sock_type = @intCast(sock_type);

    const inode = try krn.fs.Inode.allocEmpty();
    errdefer krn.mm.kfree(inode);
    inode.fops = &SocketFileOps;
    inode.data.sock = sock;

    const file = try krn.fs.File.pseudo(inode);
    errdefer file.ref.unref();

    file.mode = krn.fs.UMode.socket();
    file.flags |= krn.fs.file.O_RDWR;

    const fd = try krn.task.current.files.getNextFD();
    errdefer _ = krn.task.current.files.releaseFD(fd);

    try krn.task.current.files.setFD(fd, file);
    krn.logger.INFO("socket() created fd {d}", .{fd});
    return @intCast(fd);
}

pub fn do_bind(fd: u32, _addr_ptr: ?*anyopaque, addr_len: u32) !u32 {
    const addr_ptr = _addr_ptr orelse
        return krn.errors.PosixError.EINVAL;

    const file = krn.task.current.files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.ref();
    defer file.ref.unref();

    const sock = file.inode.data.sock orelse
        return krn.errors.PosixError.ENOTSOCK;

    const generic_sockaddr: *sockaddr = @ptrCast(@alignCast(addr_ptr));
    if (generic_sockaddr.sa_family != AF_UNIX and generic_sockaddr.sa_family != AF_LOCAL) {
        return krn.errors.PosixError.EAFNOSUPPORT;
    }

    if (addr_len < 3 or addr_len > @sizeOf(sockaddr_un)) {
        return krn.errors.PosixError.EINVAL;
    }

    const addr: *const sockaddr_un = @ptrCast(@alignCast(addr_ptr));

    const path_max = addr_len - @offsetOf(sockaddr_un, "sun_path");
    var path_len: usize = 0;
    while (path_len < path_max and addr.sun_path[path_len] != 0) : (path_len += 1) {}

    if (path_len == 0) {
        return krn.errors.PosixError.EINVAL;
    }

    if (findBoundSocket(addr.sun_path[0..path_len]) != null) {
        return krn.errors.PosixError.EADDRINUSE;
    }

    sock.lock.lock();
    @memcpy(sock.bound_path[0..path_len], addr.sun_path[0..path_len]);
    sock.bound_path_len = path_len;
    sock.lock.unlock();

    if (!registerBound(sock)) {
        sock.lock.lock();
        sock.bound_path_len = 0;
        sock.lock.unlock();
        return krn.errors.PosixError.ENOMEM;
    }

    krn.logger.INFO("bind() fd {d} to path {s}", .{fd, addr.sun_path[0..path_len]});
    return 0;
}

pub fn do_listen(fd: u32, backlog: u32) !u32 {
    const file = krn.task.current.files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.ref();
    defer file.ref.unref();

    const sock = file.inode.data.sock orelse
        return krn.errors.PosixError.ENOTSOCK;

    if (sock.bound_path_len == 0) {
        return krn.errors.PosixError.EINVAL;
    }

    sock.lock.lock();
    sock.is_listening = true;
    sock.accept_backlog = if (backlog > 0 and backlog <= MAX_BACKLOG) backlog else MAX_BACKLOG;
    sock.lock.unlock();

    krn.logger.INFO("listen() fd {d} backlog {d}", .{fd, sock.accept_backlog});
    return 0;
}

pub fn do_accept4(fd: u32, addr: u32, addr_len: u32, flags: u32) !u32 {
    _ = addr;
    _ = addr_len;
    _ = flags;

    const file = krn.task.current.files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.ref();
    defer file.ref.unref();

    const listener = file.inode.data.sock orelse
        return krn.errors.PosixError.ENOTSOCK;

    if (!listener.is_listening) {
        return krn.errors.PosixError.EINVAL;
    }

    while (true) {
        listener.lock.lock();
        if (!listener.accept_queue.isEmpty()) {
            const pending_node = listener.accept_queue.next.?;
            pending_node.del();
            pending_node.setup();
            listener.accept_count -|= 1;
            listener.lock.unlock();

            const client_sock = pending_node.entry(Socket, "pending_link");

            const server_sock = Socket.newSocket() orelse
                return krn.errors.PosixError.ENOMEM;
            errdefer krn.mm.kfree(server_sock);

            client_sock.conn = server_sock;
            server_sock.conn = client_sock;

            const new_inode = try krn.fs.Inode.allocEmpty();
            errdefer krn.mm.kfree(new_inode);
            new_inode.fops = &SocketFileOps;
            new_inode.data.sock = server_sock;

            const new_file = try krn.fs.File.pseudo(new_inode);
            errdefer new_file.ref.unref();

            new_file.mode = krn.fs.UMode.socket();
            new_file.flags |= krn.fs.file.O_RDWR;

            const new_fd = try krn.task.current.files.getNextFD();
            errdefer _ = krn.task.current.files.releaseFD(new_fd);

            try krn.task.current.files.setFD(new_fd, new_file);
            krn.logger.INFO("accept() fd {d} -> new fd {d}", .{fd, new_fd});
            return @intCast(new_fd);
        }
        listener.lock.unlock();

        listener.accept_wait.wait(true, 0);
        if (krn.task.current.sighand.hasPending())
            return krn.errors.PosixError.EINTR;
    }
}

pub fn do_connect(fd: u32, _addr_ptr: ?*anyopaque, addr_len: u32) !u32 {
    const addr_ptr = _addr_ptr orelse
        return krn.errors.PosixError.EINVAL;

    const file = krn.task.current.files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.ref();
    defer file.ref.unref();

    const sock = file.inode.data.sock orelse
        return krn.errors.PosixError.ENOTSOCK;

    if (sock.conn != null) {
        return krn.errors.PosixError.EISCONN;
    }

    const addr: *const sockaddr_un = @ptrCast(@alignCast(addr_ptr));
    if (addr.sun_family != AF_UNIX and addr.sun_family != AF_LOCAL) {
        return krn.errors.PosixError.EAFNOSUPPORT;
    }

    if (addr_len < 3 or addr_len > @sizeOf(sockaddr_un)) {
        return krn.errors.PosixError.EINVAL;
    }

    const path_max = addr_len - @offsetOf(sockaddr_un, "sun_path");
    var path_len: usize = 0;
    while (path_len < path_max and addr.sun_path[path_len] != 0) : (path_len += 1) {}

    const listener = findBoundSocket(addr.sun_path[0..path_len]) orelse
        return krn.errors.PosixError.ECONNREFUSED;

    if (!listener.is_listening) {
        return krn.errors.PosixError.ECONNREFUSED;
    }

    listener.lock.lock();
    if (listener.accept_count >= listener.accept_backlog) {
        listener.lock.unlock();
        return krn.errors.PosixError.ECONNREFUSED;
    }
    sock.pending_link.setup();
    listener.accept_queue.addTail(&sock.pending_link);
    listener.accept_count += 1;
    listener.lock.unlock();

    listener.accept_wait.wakeUpOne();

    while (sock.conn == null) {
        krn.task.current.wakeup_time = krn.currentMs() + 10;
        krn.task.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
        if (krn.task.current.sighand.hasPending())
            return krn.errors.PosixError.EINTR;
    }

    krn.logger.INFO("connect() fd {d} connected", .{fd});
    return 0;
}

pub fn do_recvfrom(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    var sock: *Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;
    sock.lock.lock();
    defer sock.lock.unlock();

    while (sock.rb.isEmpty()) {
        if (sock.conn == null) {
            return krn.errors.PosixError.ENOTCONN;
        }

        var wq_node = krn.wq.WaitQueueNode.init(krn.task.current);
        wq_node.setup();

        sock.rw_queue.addToQueue(&wq_node);
        sock.lock.unlock();
        sock.rw_queue.waitIfInQueue(&wq_node, true, 0);

        if (krn.task.current.sighand.hasPending()) {
            sock.lock.lock();
            return krn.errors.PosixError.EINTR;
        }

        sock.lock.lock();
    }
    const ret_size: usize = sock.rb.readInto(buf[0..size]);
    if (sock.conn) |remote| {
        remote.rw_queue.wakeUpOne();
    }
    return ret_size;
}

pub fn do_sendto(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    var sock: *Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;
    var remote = sock.conn orelse
        return krn.errors.PosixError.ENOTCONN;

    remote.lock.lock();
    defer remote.lock.unlock();
    while (remote.rb.isFull()) {
        var wq_node = krn.wq.WaitQueueNode.init(krn.task.current);
        wq_node.setup();

        sock.rw_queue.addToQueue(&wq_node);
        remote.lock.unlock();
        sock.rw_queue.waitIfInQueue(&wq_node, true, 0);
        if (krn.task.current.sighand.hasPending()) {
            remote.lock.lock();
            return krn.errors.PosixError.EINTR;
        }

        if (sock.conn == null) {
            remote.lock.lock();
            return krn.errors.PosixError.ENOTCONN;
        }

        remote.lock.lock();
    }
    defer remote.rw_queue.wakeUpOne();
    for (buf[0..size], 0..) |ch, idx| {
        if (!remote.rb.push(ch)) {
            krn.logger.WARN("sendto: sent {d} from {d}", .{idx, size});
            return idx;
        }
    }
    krn.logger.WARN("sendto: sent {d} from {d} (all)", .{size, size});
    return size;
}

pub fn open(base: *krn.fs.File, inode: *krn.fs.Inode) !void {
    _ = base;
    _ = inode;
}

pub fn close(base: *krn.fs.File) void {
    if (base.inode.data.sock) |sock| {
        base.inode.data.sock = null;
        sock.delete();
    }
}

pub fn read(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    return try do_recvfrom(base, buf, size);
}

pub fn write(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    return try do_sendto(base, buf, size);
}

pub fn sock_poll(base: *krn.fs.File, pollfd: *krn.poll.PollFd) !u32 {
    const sock = base.inode.data.sock orelse return 0;
    var ready: u32 = 0;

    if (sock.is_listening) {
        if (pollfd.events & krn.poll.POLLIN != 0) {
            sock.lock.lock();
            const has_pending = !sock.accept_queue.isEmpty();
            sock.lock.unlock();
            if (has_pending) {
                pollfd.revents |= krn.poll.POLLIN;
                ready = 1;
            }
        }
        return ready;
    }

    if (pollfd.events & krn.poll.POLLIN != 0) {
        sock.lock.lock();
        const avail = sock.rb.available();
        sock.lock.unlock();
        if (avail > 0) {
            pollfd.revents |= krn.poll.POLLIN;
            ready = 1;
        }
    }
    if (pollfd.events & krn.poll.POLLOUT != 0) {
        if (sock.conn != null) {
            if (!sock.conn.?.rb.isFull()) {
                pollfd.revents |= krn.poll.POLLOUT;
                ready = 1;
            }
        }
    }
    return ready;
}

pub const SocketFileOps: krn.fs.FileOps = krn.fs.FileOps{
    .open = open,
    .close = close,
    .write = write,
    .read = read,
    .lseek = null,
    .readdir = null,
    .poll = sock_poll,
};
