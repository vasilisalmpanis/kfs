const std = @import("std");
const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const arch = @import("arch");
const IoVec = @import("./read.zig").IoVec;

const CallType = enum(u8) {
    SYS_SOCKET = 1,	// 1   sys_socket(2)
    SYS_BIND,	        // 2   sys_bind(2)
    SYS_CONNECT,	// 3   sys_connect(2)
    SYS_LISTEN,	        // 4   sys_listen(2)
    SYS_ACCEPT,	        // 5   sys_accept(2)
    SYS_GETSOCKNAME,	// 6   sys_getsockname(2)
    SYS_GETPEERNAME,	// 7   sys_getpeername(2)
    SYS_SOCKETPAIR,	// 8   sys_socketpair(2)
    SYS_SEND,	        // 9   sys_send(2))
    SYS_RECV,	        // 10  sys_recv(2))
    SYS_SENDTO,	        // 11  sys_sendto(2)
    SYS_RECVFROM,	// 12  sys_recvfrom(2)
    SYS_SHUTDOWN,	// 13  sys_shutdown(2)
    SYS_SETSOCKOPT,	// 14  sys_setsockopt(2)
    SYS_GETSOCKOPT,	// 15  sys_getsockopt(2)
    SYS_SENDMSG,	// 16  sys_sendmsg(2)
    SYS_RECVMSG,	// 17  sys_recvmsg(2)
    SYS_ACCEPT4,	// 18  sys_accept4(2)
    SYS_RECVMMSG,	// 19  sys_recvmmsg(2)
    SYS_SENDMMSG,	// 20  sys_sendmmsg(2)
    _
};

pub fn socketcall(call: i32, args: [*]u32) !u32 {
    if (call < 1 or call > 20) {
        return errors.EINVAL;
    }
    const call_type: CallType = @enumFromInt(call);
    krn.logger.INFO("socketcall: {any} {any}", .{call_type, args});
    switch (call_type) {
        .SYS_SOCKET => return try krn.socket.do_socket(
            @intCast(args[0]),
            @intCast(args[1]),
            @intCast(args[2]),
        ),
        .SYS_BIND => return try krn.socket.do_bind(
            @bitCast(args[0]), @ptrFromInt(args[1]), args[2],
        ),
        .SYS_CONNECT => return try krn.socket.do_connect(
            @bitCast(args[0]), @ptrFromInt(args[1]), args[2],
        ),
        .SYS_LISTEN => return try krn.socket.do_listen(
            @bitCast(args[0]), args[1],
        ),
        .SYS_ACCEPT => return try krn.socket.do_accept4(
            @bitCast(args[0]), args[1], args[2], 0,
        ),
        .SYS_SOCKETPAIR => return try socketpair(
            @intCast(args[0]),
            @intCast(args[1]),
            @intCast(args[2]),
            @ptrFromInt(args[3]),
        ),
        .SYS_RECVFROM => return try recvfrom(
            @bitCast(args[0]),
            @ptrFromInt(args[1]),
            args[2],
            args[3],
            args[4],
            @bitCast(args[5]),
        ),
        .SYS_SENDTO => return try sendto(
            @bitCast(args[0]),
            @ptrFromInt(args[1]),
            args[2],
            args[3],
            args[4],
            @bitCast(args[5]),
        ),
        .SYS_ACCEPT4 => return try krn.socket.do_accept4(
            @bitCast(args[0]), args[1], args[2], args[3],
        ),
        .SYS_RECVMSG => return try recvmsg(@bitCast(args[0]), @ptrFromInt(args[1]), @bitCast(args[2])),
        .SYS_SENDMSG => return try sendmsg(@bitCast(args[0]), @ptrFromInt(args[1]), @bitCast(args[2])),
        else => {
            return errors.EINVAL;
        },
    }
    return 0;
}

pub fn socket(family: u16, sock_type: u16, protocol: u8) !u32 {
    return try krn.socket.do_socket(family, sock_type, protocol);
}

pub fn bind(fd: i32, addr: u32, addr_len: u32) !u32 {
    return try krn.socket.do_bind(fd, @ptrFromInt(addr), addr_len);
}

pub fn connect(fd: i32, addr: u32, addr_len: u32) !u32 {
    return try krn.socket.do_connect(fd, @ptrFromInt(addr), addr_len);
}

pub fn listen(fd: i32, backlog: u32) !u32 {
    return try krn.socket.do_listen(fd, backlog);
}

pub fn accept4(fd: i32, addr: u32, addr_len: u32, flags: u32) !u32 {
    return try krn.socket.do_accept4(fd, addr, addr_len, flags);
}

pub fn socketpair(family: u32, s_type: u32, protocol: u32, usockvec: ?*[2]i32) !u32 {
    if (protocol > std.math.maxInt(u8))
        return errors.EPROTONOSUPPORT;
    return try krn.socket.do_socketpair(family, s_type, @intCast(protocol), usockvec);
}

pub fn recvfrom(
    fd: i32,
    ubuff: ?*anyopaque,
    size: u32,
    flags: u32,
    addr: u32,
    addr_len: i32
) !u32 {
    _ = addr;
    _ = addr_len;
    _ = flags;
    if (ubuff == null) {
        return errors.EFAULT;
    }
    const sock = try krn.socket.sockfdLookup(fd);
    defer sock.file.ref.put();
    return try krn.socket.do_recvfrom(sock.file, @ptrCast(ubuff), size);
}

pub fn sendto(fd: i32, buff: ?*anyopaque, len: usize, flags: u32, addr: u32, addr_len: i32) !u32 {
    _ = flags;
    _ = addr;
    _ = addr_len;
    if (buff == null) {
        return errors.EFAULT;
    }
    if (len > 128) {
        return errors.EFAULT;
    }
    const sock = try krn.socket.sockfdLookup(fd);
    defer sock.file.ref.put();
    return try krn.socket.do_sendto(sock.file, @ptrCast(buff), len);
}

const MsgHdr = struct {
    name:       ?*krn.socket.sockaddr,
    namelen:    i32,
    iov:        ?[*]IoVec,
    iovlen:     usize,
    control:    ?*anyopaque,
    controllen: usize,
    flags:      u32,
};

pub fn sendmsg(sockfd: i32, _msg: ?*MsgHdr, flags: i32) !u32 {
    _ = flags;
    const msg = _msg orelse
        return errors.EFAULT;
    const iov = msg.iov orelse
        return errors.EFAULT;
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    var sent: usize = 0;
    for (iov, 0..msg.iovlen) |*_v, _| {
        sent += try krn.socket.do_sendto(
            sock.file,
            @ptrCast(_v.base),
            _v.len
        );
    }
    return sent;
}

pub fn recvmsg(sockfd: i32, _msg: ?*MsgHdr, flags: i32) !u32 {
    _ = flags;
    const msg = _msg orelse
        return errors.EFAULT;
    const iov = msg.iov orelse
        return errors.EFAULT;
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    var received: usize = 0;
    for (iov, 0..msg.iovlen) |*_v, _| {
        const recv_curr = try krn.socket.do_recvfrom(
            sock.file,
            @ptrCast(_v.base),
            _v.len
        );
        received += recv_curr;
        if (recv_curr < _v.len)
            break ;
    }
    return received;
}

pub fn getpeername(
    sockfd: i32,
    _addr: ?*krn.socket.sockaddr,
    _addrlen: ?*i32,
) !u32 {
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    const addrlen = _addrlen orelse
        return errors.EINVAL;
    const addr = _addr orelse
        return errors.EINVAL;
    if (addrlen.* < 0)
        return errors.EINVAL;
    const ret = try sock.ops.getName(sock, addr, true);
    addrlen.* = @intCast(ret);
    return 0;
}

pub fn getsockname(
    sockfd: i32,
    _addr: ?*krn.socket.sockaddr,
    _addrlen: ?*i32,
) !u32 {
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    const addrlen = _addrlen orelse
        return errors.EINVAL;
    const addr = _addr orelse
        return errors.EINVAL;
    if (addrlen.* < 0)
        return errors.EINVAL;

    const ret = try sock.ops.getName(sock, addr, false);
    addrlen.* = @intCast(ret);
    return 0;
}

pub fn getsockopt(
    sockfd: i32,
    level: i32,
    optname: i32,
    optval: ?*anyopaque,
    optlen: ?*i32,
) !u32 {
    _ = optlen;
    _ = optname;
    _ = level;
    _ = optval orelse
        return errors.EFAULT;
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    return 0;
}

const SOL_SOCKET: i32 = 1;

pub fn setsockopt(
    sockfd: i32,
    level: i32,
    optname: i32,
    optval: ?*anyopaque,
    optlen: i32,
) !u32 {
    _ = optname;
    _ = optlen;
    _ = optval orelse
        return errors.EFAULT;
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    krn.logger.INFO("setsockopt\n",.{});
    if (level != SOL_SOCKET)
        return errors.EOPNOTSUPP;
    return 0;
}

pub fn shutdown(sockfd: i32, how: i32) !u32 {
    _ = how;
    const sock = try krn.socket.sockfdLookup(sockfd);
    defer sock.file.ref.put();

    return 0;
}
