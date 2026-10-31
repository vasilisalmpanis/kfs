const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const SOCK_STREAM: u16 = 1;
pub const SOCK_DGRAM: u16 = 2;

pub const SOCK_TYPE_MASK: u32 = 0xf;
pub const SOCK_NONBLOCK: u32 = krn.fs.file.O_NONBLOCK;
pub const SOCK_CLOEXEC: u32 = krn.fs.file.O_CLOEXEC;

pub const SOCK_SUPPORTED: u32 = SOCK_STREAM | SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK;

pub const MAX_UNIX_PATH: usize = 108;
pub const MAX_BACKLOG: usize = 16;
const SOCK_BUFFER_SIZE = 4096;

pub const AF_UNSPEC     :u32 = 0;
pub const AF_UNIX       :u32 = 1;  // Unix domain sockets
pub const AF_LOCAL      :u32 = AF_UNIX;  // POSIX name for AF_UNIX
pub const AF_INET       :u32 = 2;  // Internet IP Protocol
pub const AF_AX25       :u32 = 3;  // Amateur Radio AX.25
pub const AF_IPX        :u32 = 4;  // Novell IPX
pub const AF_APPLETALK  :u32 = 5;  // AppleTalk DDP
pub const AF_NETROM     :u32 = 6;  // Amateur Radio NET/ROM
pub const AF_BRIDGE     :u32 = 7;  // Multiprotocol bridge
pub const AF_ATMPVC     :u32 = 8;  // ATM PVCs
pub const AF_X25        :u32 = 9;  // Reserved for X.25 project
pub const AF_INET6      :u32 = 10; // IP version 6
pub const AF_ROSE       :u32 = 11; // Amateur Radio X.25 PLP
pub const AF_DECnet     :u32 = 12; // Reserved for DECnet project
pub const AF_NETBEUI    :u32 = 13; // Reserved for 802.2LLC project
pub const AF_SECURITY   :u32 = 14; // Security callback pseudo AF
pub const AF_KEY        :u32 = 15; // PF_KEY key management API
pub const AF_NETLINK    :u32 = 16;
pub const AF_ROUTE      :u32 = AF_NETLINK; // Alias to emulate 4.4BSD
pub const AF_PACKET     :u32 = 17; // Packet family
pub const AF_ASH        :u32 = 18; // Ash
pub const AF_ECONET     :u32 = 19; // Acorn Econet
pub const AF_ATMSVC     :u32 = 20; // ATM SVCs
pub const AF_RDS        :u32 = 21; // RDS sockets
pub const AF_SNA        :u32 = 22; // Linux SNA Project (nutters!)
pub const AF_IRDA       :u32 = 23; // IRDA sockets
pub const AF_PPPOX      :u32 = 24; // PPPoX sockets
pub const AF_WANPIPE    :u32 = 25; // Wanpipe API Sockets
pub const AF_LLC        :u32 = 26; // Linux LLC
pub const AF_IB         :u32 = 27; // Native InfiniBand address
pub const AF_MPLS       :u32 = 28; // MPLS
pub const AF_CAN        :u32 = 29; // Controller Area Network
pub const AF_TIPC       :u32 = 30; // TIPC sockets
pub const AF_BLUETOOTH  :u32 = 31; // Bluetooth sockets
pub const AF_IUCV       :u32 = 32; // IUCV sockets
pub const AF_RXRPC      :u32 = 33; // RxRPC sockets
pub const AF_ISDN       :u32 = 34; // mISDN sockets
pub const AF_PHONET     :u32 = 35; // Phonet sockets
pub const AF_IEEE802154 :u32 = 36; // IEEE802154 sockets
pub const AF_CAIF       :u32 = 37; // CAIF sockets
pub const AF_ALG        :u32 = 38; // Algorithm sockets
pub const AF_NFC        :u32 = 39; // NFC sockets
pub const AF_VSOCK      :u32 = 40; // vSockets
pub const AF_KCM        :u32 = 41; // Kernel Connection Multiplexor
pub const AF_QIPCRTR    :u32 = 42; // Qualcomm IPC Router
pub const AF_SMC        :u32 = 43; // smc sockets: reserve number for
                                   // PF_SMC protocol family that
                                   // reuses AF_INET address family
                                   //
pub const AF_XDP        :u32 = 44; // XDP sockets
pub const AF_MCTP       :u32 = 45; // Management component
                                   // transport protocol
pub const AF_MAX        :u32 = 46; // For now..


pub const ProtocolFamily = struct {
    create: * const fn (*Socket) anyerror!void
};
pub var net_families: [AF_MAX]?*const ProtocolFamily = @splat(null);

pub const sockaddr_un = extern struct {
    sun_family: u16,
    sun_path: [MAX_UNIX_PATH]u8,
};

pub const sockaddr = extern struct {
    sa_family: u16,
    sa_data: [14]u8,
};

pub const sockaddr_in = extern struct {
    family: u16 = AF_INET,
    port: u16,
    addr: u32,
    zero: [8]u8 = @splat(0),
};

pub const ProtocolOps = struct {
    ioctl: *const fn(*Socket, op: u32, data: usize) anyerror!u32,
};

pub const Socket = struct {
    _buffer: [SOCK_BUFFER_SIZE]u8,
    rb: krn.ringbuf.RingBuf,
    conn: ?*Socket,
    list: lst.ListHead,
    lock: krn.Spinlock = krn.Spinlock.init(),

    sock_type: u16 = SOCK_STREAM,
    is_listening: bool = false,
    bound_path: [MAX_UNIX_PATH]u8 = @splat(0),
    bound_path_len: usize = 0,

    accept_queue: lst.ListHead = lst.ListHead.init(),
    accept_count: usize = 0,
    accept_backlog: usize = MAX_BACKLOG,
    accept_wait: krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),

    rw_queue: krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),

    pending_link: lst.ListHead = lst.ListHead.init(),
    ops: * const ProtocolOps,

    pub fn setup(self: *Socket) void {
        self._buffer = @splat(0);
        self.rb = krn.ringbuf.RingBuf._init(self._buffer[0..SOCK_BUFFER_SIZE]) catch {
            @panic("Make buffer size a power of two.");
        };
        self.conn = null;
        self.list.next = &self.list;
        self.list.prev = &self.list;
        self.lock = krn.Spinlock.init();
        self.sock_type = SOCK_STREAM;
        self.is_listening = false;
        self.bound_path = @splat(0);
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
        self.pending_link.del();
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
    
    pub fn getName(self: *Socket, addr: *sockaddr, len: *i32) void {
        addr.sa_family = AF_UNIX;
        var addr_un = @as(*sockaddr_un, @ptrCast(addr));
        if (self.bound_path_len > 0) {
            @memcpy(
                addr_un.sun_path[0..self.bound_path_len],
                self.bound_path[0..self.bound_path_len]
            );
            len.* = @intCast(@sizeOf(u16) + self.bound_path_len + 1);
        } else {
            addr_un.sun_path[0] = 0;
            len.* = @sizeOf(u16) + 1;
        }
    }
};

const MAX_BOUND_SOCKETS: usize = 32;
var bound_sockets: [MAX_BOUND_SOCKETS]?*Socket = @splat(null);

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
    if (family >= AF_MAX)
        return krn.errors.PosixError.EAFNOSUPPORT;
    const net_family = net_families[family] orelse
        return krn.errors.PosixError.EAFNOSUPPORT;

    if (sock_type & ~SOCK_SUPPORTED != 0) {
        return krn.errors.PosixError.ESOCKTNOSUPPORT;
    }
    const sock = Socket.newSocket() orelse return krn.errors.PosixError.ENOMEM;
    errdefer krn.mm.kfree(sock);
    sock.sock_type = @intCast(sock_type & SOCK_TYPE_MASK);

    const inode = try krn.fs.Inode.allocEmpty();
    errdefer krn.mm.kfree(inode);
    inode.fops = &SocketFileOps;
    inode.data.sock = sock;

    const file = try krn.fs.File.pseudo(inode);
    errdefer file.ref.put();

    file.mode = krn.fs.UMode.socket();
    file.flags |= krn.fs.file.O_RDWR;


    try net_family.create(sock);

    const fd = try krn.task.current().files.getNextFD();
    errdefer _ = krn.task.current().files.releaseFD(fd);

    if (sock_type & SOCK_NONBLOCK != 0)
        file.flags |= SOCK_NONBLOCK;
    if (sock_type & SOCK_CLOEXEC != 0) {
        krn.task.current().files.closexec.set(fd);
    }
    errdefer krn.task.current().files.closexec.unset(fd);

    try krn.task.current().files.setFD(fd, file);
    krn.logger.INFO("socket() created fd {d}", .{fd});
    return @intCast(fd);
}

pub fn do_bind(fd: u32, _addr_ptr: ?*anyopaque, addr_len: u32) !u32 {
    const addr_ptr = _addr_ptr orelse
        return krn.errors.PosixError.EINVAL;

    const file = krn.task.current().files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.get();
    defer file.ref.put();

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
    const path_len = unixNameLen(addr.sun_path[0..path_max]);

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
    const file = krn.task.current().files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.get();
    defer file.ref.put();

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

    const file = krn.task.current().files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.get();
    defer file.ref.put();

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

            const new_inode = try krn.fs.Inode.allocEmpty();
            errdefer krn.mm.kfree(new_inode);
            new_inode.fops = &SocketFileOps;
            new_inode.data.sock = server_sock;

            const new_file = try krn.fs.File.pseudo(new_inode);
            errdefer new_file.ref.put();

            new_file.mode = krn.fs.UMode.socket();
            new_file.flags |= krn.fs.file.O_RDWR;

            const new_fd = try krn.task.current().files.getNextFD();
            errdefer _ = krn.task.current().files.releaseFD(new_fd);

            try krn.task.current().files.setFD(new_fd, new_file);
            krn.logger.INFO("accept() fd {d} -> new fd {d}", .{fd, new_fd});

            client_sock.conn = server_sock;
            server_sock.conn = client_sock;

            return @intCast(new_fd);
        }
        listener.lock.unlock();

        if (file.flags & krn.fs.file.O_NONBLOCK != 0)
            return krn.errors.PosixError.EAGAIN;
        listener.accept_wait.wait(true, 0);
        if (krn.task.current().hasPendingSignal())
            return krn.errors.PosixError.ERESTARTSYS;
    }
}

pub fn do_connect(fd: u32, _addr_ptr: ?*anyopaque, addr_len: u32) !u32 {
    const addr_ptr = _addr_ptr orelse
        return krn.errors.PosixError.EINVAL;

    const file = krn.task.current().files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.get();
    defer file.ref.put();

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
    const path_len = unixNameLen(addr.sun_path[0..path_max]);

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
        if (file.flags & krn.fs.file.O_NONBLOCK != 0)
            return krn.errors.PosixError.EAGAIN;

        krn.task.current().wakeup_time = krn.currentMs() + 10;
        krn.task.current().state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
        if (krn.task.current().hasPendingSignal())
            return krn.errors.PosixError.ERESTARTSYS;
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
        if (base.flags & krn.fs.file.O_NONBLOCK != 0)
            return krn.errors.PosixError.EAGAIN;

        var wq_node = krn.wq.WaitQueueNode.init(krn.task.current());
        wq_node.setup();

        sock.rw_queue.addToQueue(&wq_node);
        sock.lock.unlock();
        sock.rw_queue.waitIfInQueue(&wq_node, true, 0);

        if (krn.task.current().hasPendingSignal()) {
            sock.lock.lock();
            return krn.errors.PosixError.ERESTARTSYS;
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
        if (base.flags & krn.fs.file.O_NONBLOCK != 0)
            return krn.errors.PosixError.EAGAIN;

        var wq_node = krn.wq.WaitQueueNode.init(krn.task.current());
        wq_node.setup();

        sock.rw_queue.addToQueue(&wq_node);
        remote.lock.unlock();
        sock.rw_queue.waitIfInQueue(&wq_node, true, 0);
        if (krn.task.current().hasPendingSignal()) {
            remote.lock.lock();
            return krn.errors.PosixError.ERESTARTSYS;
        }

        if (sock.conn == null) {
            remote.lock.lock();
            return krn.errors.PosixError.ENOTCONN;
        }

        remote.lock.lock();
    }
    defer remote.rw_queue.wakeUpOne();
    for (buf[0..size], 0..) |ch, idx| {
        if (!remote.rb.push(ch))
            return idx;
    }
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

pub fn sock_poll(
    base: *krn.fs.File,
    pollfd: *krn.poll.PollFd,
    poll_table: ?*krn.poll.PollTable,
) !u32 {
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
        if (ready == 0 and pollfd.events & krn.poll.POLLIN != 0) {
            if (poll_table) |pt|
                try pt.addNode(&sock.accept_wait);
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
    if (
        ready == 0
        and pollfd.events & (krn.poll.POLLIN | krn.poll.POLLOUT) != 0
    ) {
        if (poll_table) |pt|
            try pt.addNode(&sock.rw_queue);
    }
    return ready;
}

fn sock_ioctl(base: *krn.fs.File, op: u32, data: usize) !u32 {
    const sock = base.inode.data.sock orelse return 0;
    return try sock.ops.ioctl(sock, op, data);
}

pub const SocketFileOps: krn.fs.FileOps = krn.fs.FileOps{
    .open = open,
    .close = close,
    .write = write,
    .read = read,
    .lseek = null,
    .readdir = null,
    .poll = sock_poll,
    .ioctl = sock_ioctl
};
