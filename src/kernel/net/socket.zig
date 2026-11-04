const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const SOCK_STREAM: u16      = 1;
pub const SOCK_DGRAM: u16       = 2;
pub const SOCK_RAW: u16 	    = 3;
pub const SOCK_RDM: u16 	    = 4;
pub const SOCK_SEQPACKET: u16   = 5;
pub const SOCK_DCCP: u16    	= 6;
pub const SOCK_PACKET: u16  	= 10;

pub const SOCK_TYPE_MASK: u16 = 0xf;
pub const SOCK_NONBLOCK: u32 = krn.fs.file.O_NONBLOCK;
pub const SOCK_CLOEXEC: u32 = krn.fs.file.O_CLOEXEC;

pub const SOCK_SUPPORTED: u32 = SOCK_STREAM | SOCK_DGRAM | SOCK_RAW | SOCK_CLOEXEC | SOCK_NONBLOCK;

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
    create: * const fn (socket_type: u16, protocol: u8) anyerror!*Socket
};

pub var net_families: [AF_MAX]?*const ProtocolFamily = @splat(null);

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
    ioctl:      *const fn(*Socket, op: u32, data: usize) anyerror!usize,
    getName:    *const fn(*Socket, addr: *sockaddr, peer: bool) anyerror!usize,
    bind:       *const fn(*Socket, addr: *anyopaque, addrlen: u32) anyerror!void,
    listen:     *const fn(*Socket, backlog: u32) anyerror!void,
    connect:    *const fn(*Socket, addr_ptr: *anyopaque, addrlen: u32) anyerror!void,
    accept:     *const fn(*Socket) anyerror!u32,
    recvfrom:   *const fn(*Socket, buf: [*]u8, size: usize) anyerror!usize,
    sendto:     *const fn(*Socket, buf: [*]const u8, size: usize) anyerror!usize,
    poll:       *const fn(*Socket, pollfd: *krn.poll.PollFd, poll_table: ?*krn.poll.PollTable) anyerror!usize,
    socketpair: *const fn(*Socket, *Socket) anyerror!void,
    release:    *const fn(*Socket) anyerror!void,
};

pub const Socket = struct {
    socket_type: u16 = SOCK_STREAM,
    protocol: u8 = 0, // IPPROTO_ICMP etc
    family: u16 = 0, // AF_UNIX etc
    list: lst.ListHead,
    lock: krn.Spinlock = krn.Spinlock.init(),
    rw_queue: krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),
    file: *krn.fs.File,
    ops: * const ProtocolOps,

    pub fn setup(
        self: *Socket,
        family: u16,
        socket_type: u16,
        protocol: u8
    ) void {
        self.socket_type = socket_type & SOCK_TYPE_MASK;
        self.protocol = protocol;
        self.family = family;
        self.list.setup();
        self.lock = krn.Spinlock.init();
        self.rw_queue.setup();
    }
};

pub fn sockAllocFd(sock: *Socket, flags: u32) !u32 {
    const inode = try krn.fs.Inode.allocEmpty();
    errdefer krn.mm.kfree(inode);
    inode.fops = &SocketFileOps;
    inode.data.sock = sock;

    sock.file = try krn.fs.File.pseudo(inode);
    errdefer sock.file.ref.put();

    sock.file.mode = krn.fs.UMode.socket();
    sock.file.flags |= krn.fs.file.O_RDWR;
    if (flags & SOCK_NONBLOCK != 0)
        sock.file.flags |= SOCK_NONBLOCK;

    const files = krn.task.current().files;
    const fd = try files.getNextFD();
    errdefer _ = files.releaseFD(fd);

    if (flags & SOCK_CLOEXEC != 0)
        files.closexec.set(fd);
    errdefer files.closexec.unset(fd);

    try files.setFD(fd, sock.file);
    return @intCast(fd);
}

fn lookupFamily(family: u32, sock_type: u32) !*const ProtocolFamily {
    if (family >= AF_MAX)
        return krn.errors.PosixError.EAFNOSUPPORT;
    const net_family = net_families[family] orelse
        return krn.errors.PosixError.EAFNOSUPPORT;
    if (sock_type & ~SOCK_SUPPORTED != 0)
        return krn.errors.PosixError.ESOCKTNOSUPPORT;
    return net_family;
}

pub fn do_socket(family: u16, sock_type: u16, protocol: u8) !u32 {
    const net_family = try lookupFamily(family, sock_type);
    const sock = try net_family.create(sock_type, protocol);
    errdefer sock.ops.release(sock) catch {};

    const fd = try sockAllocFd(sock, sock_type);
    krn.logger.INFO("socket() created fd {d}", .{fd});
    return fd;
}

pub fn do_socketpair(
    family: u32,
    sock_type: u32,
    protocol: u8,
    _usockvec: ?*[2]i32
) !u32 {
    const usockvec = _usockvec orelse
        return krn.errors.PosixError.EFAULT;
    const net_family = try lookupFamily(family, sock_type);
    const base_type: u16 = @intCast(sock_type & SOCK_TYPE_MASK);

    const sock_a = try net_family.create(base_type, protocol);
    errdefer sock_a.ops.release(sock_a) catch {};
    const sock_b = try net_family.create(base_type, protocol);
    errdefer sock_b.ops.release(sock_b) catch {};
    try sock_a.ops.socketpair(sock_a, sock_b);

    const fd_a = try sockAllocFd(sock_a, sock_type);
    errdefer _ = krn.task.current().files.releaseFD(fd_a);
    const fd_b = try sockAllocFd(sock_b, sock_type);

    usockvec[0] = @intCast(fd_a);
    usockvec[1] = @intCast(fd_b);
    return 0;
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
    try sock.ops.bind(sock, addr_ptr, addr_len);
    return 0;
}

pub fn do_listen(fd: u32, backlog: u32) !u32 {
    const file = krn.task.current().files.fds.get(fd) orelse
        return krn.errors.PosixError.EBADF;
    file.ref.get();
    defer file.ref.put();

    const sock = file.inode.data.sock orelse
        return krn.errors.PosixError.ENOTSOCK;

    try sock.ops.listen(sock, backlog);

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

    return try listener.ops.accept(listener);
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

    try sock.ops.connect(sock, addr_ptr, addr_len);
    krn.logger.INFO("connect() fd {d} connected", .{fd});
    return 0;
}

pub fn do_recvfrom(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    var sock: *Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;

    return try sock.ops.recvfrom(sock, buf, size);
}

pub fn do_sendto(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    var sock: *Socket = undefined;
    sock = base.inode.data.sock orelse
        return krn.errors.PosixError.EBADF;
    return try sock.ops.sendto(sock, buf, size);
}

pub fn open(base: *krn.fs.File, inode: *krn.fs.Inode) !void {
    _ = base;
    _ = inode;
}

pub fn close(base: *krn.fs.File) void {
    if (base.inode.data.sock) |sock| {
        base.inode.data.sock = null;
        sock.ops.release(sock) catch {};
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
    return try sock.ops.poll(sock, pollfd, poll_table);
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
