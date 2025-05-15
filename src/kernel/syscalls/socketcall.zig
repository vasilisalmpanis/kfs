const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const krn = @import("../main.zig");
const arch = @import("arch");

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

pub fn socketcall(call: i32, args: [*]u32) i32 {
    krn.logger.INFO("socketcall: {d} {any}", .{call, args});
    if (call < 1 or call > 20) {
        return -errors.EINVAL;
    }
    const call_type: CallType = @enumFromInt(call);
    switch (call_type) {
        .SYS_SOCKETPAIR => return socketpair(
            @intCast(args[0]),
            @intCast(args[1]),
            @intCast(args[2]),
            @ptrFromInt(args[3]),
        ),
        .SYS_RECVFROM => return recvfrom(
            @intCast(args[0]),
            @ptrFromInt(args[1]),
            args[2],
            args[3],
            args[4],
            @intCast(args[5]),
        ),
        .SYS_SENDTO => return sendto(
            @intCast(args[0]),
            @ptrFromInt(args[1]),
            args[2],
            args[3],
            args[4],
            @intCast(args[5]),
        ),
        else => {
            return -errors.EINVAL;
        },
    }
    return 0;
}

pub fn socketpair(family: i32, s_type: i32, protocol: i32, usockvec: [*]i32) i32 {
    krn.logger.INFO("socketpair: {d} {d} {d} {any}", .{family, s_type, protocol, usockvec});
    if (krn.socket.newSocket()) |sock_a| {
        if (krn.socket.newSocket()) |sock_b| {
            sock_a.conn = sock_b;
            sock_b.conn = sock_a;
            usockvec[0] = @intCast(sock_a.id);
            usockvec[1] = @intCast(sock_b.id);
        } else {
            sock_a.delete();
            return -errors.ENOMEM;
        }
    } else {
        return -errors.ENOMEM;
    }
    return 0;
}

pub fn recvfrom(
    fd: i32,
    ubuff: ?*anyopaque,
    size: u32,
    flags: u32,
    addr: u32,
    addr_len: i32
) i32 {
    _ = addr;
    _ = addr_len;
    _ = flags;
    if (ubuff == null) {
        return -errors.EFAULT;
    }
    if (krn.socket.findById(@intCast(fd))) |sock| {
        const u_buff: [*]u8 = @ptrCast(ubuff);
        sock.lock.lock();
        const avail = sock.ringbuf.len();
        const to_read = if (avail > size) size else avail;
        defer sock.lock.unlock();
        sock.ringbuf.readFirstAssumeLength(u_buff[0..to_read], to_read);
        return @intCast(to_read);
    } else {
        return -errors.EBADF;
    }
    return 0;
}

pub fn sendto(fd: i32, buff: ?*anyopaque, len: usize, flags: u32, addr: u32, addr_len: i32) i32 {
    _ = flags;
    _ = addr;
    _ = addr_len;
    if (buff == null) {
        return -errors.EFAULT;
    }
    if (len > 128) {
        return -errors.EFAULT;
    }
    if (krn.socket.findById(@intCast(fd))) |sock| {
        if (sock.conn) |remote| {
            const ubuff: [*]u8 = @ptrCast(buff);
            remote.lock.lock();
            defer remote.lock.unlock();
            const free_space = remote.ringbuf.data.len - remote.ringbuf.len();
            const to_write = if (free_space > len) len else free_space;
            remote.ringbuf.writeSliceAssumeCapacity(ubuff[0..to_write]);
            return @intCast(len);
        } else {
            return -errors.ENOTCONN;
        }
    } else {
        return -errors.EBADF;
    }
    return 0;
}
