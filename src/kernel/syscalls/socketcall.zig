const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
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

pub fn socketcall(call: i32, args: [*]u32) !u32 {
    if (call < 1 or call > 20) {
        return errors.EINVAL;
    }
    const call_type: CallType = @enumFromInt(call);
    krn.logger.INFO("socketcall: {any} {any}", .{call_type, args});
    switch (call_type) {
        .SYS_SOCKETPAIR => return try socketpair(
            @intCast(args[0]),
            @intCast(args[1]),
            @intCast(args[2]),
            @ptrFromInt(args[3]),
        ),
        .SYS_RECVFROM => return try recvfrom(
            @intCast(args[0]),
            @ptrFromInt(args[1]),
            args[2],
            args[3],
            args[4],
            @intCast(args[5]),
        ),
        .SYS_SENDTO => return try sendto(
            @intCast(args[0]),
            @ptrFromInt(args[1]),
            args[2],
            args[3],
            args[4],
            @intCast(args[5]),
        ),
        else => {
            return errors.EINVAL;
        },
    }
    return 0;
}

pub fn socketpair(family: i32, s_type: i32, protocol: i32, usockvec: [*]i32) !u32 {
    krn.logger.INFO("socketpair: {d} {d} {d} {any}", .{family, s_type, protocol, usockvec});
    var file1: *krn.fs.File = undefined;
    var file2: *krn.fs.File = undefined;
    const fd1: u32 = try krn.task.current.files.getNextFD();
    const fd2: u32 = try krn.task.current.files.getNextFD();
    errdefer _ = krn.task.current.files.releaseFD(fd1);
    errdefer _ = krn.task.current.files.releaseFD(fd2);
    if (krn.socket.Socket.newSocket()) |sock_a| {
        errdefer krn.mm.kfree(sock_a);
        if (krn.socket.Socket.newSocket()) |sock_b| {
            errdefer krn.mm.kfree(sock_b);
            sock_a.conn = sock_b;
            sock_b.conn = sock_a;
            const inode1 = try krn.fs.Inode.allocEmpty();
            errdefer krn.mm.kfree(inode1);
            inode1.fops = &krn.socket.SocketFileOps;
            inode1.data.sock = sock_a;
            const inode2 = try krn.fs.Inode.allocEmpty();
            errdefer krn.mm.kfree(inode2);
            inode2.fops = &krn.socket.SocketFileOps;
            inode2.data.sock = sock_b;
            file1 = try krn.fs.File.pseudo(inode1);
            errdefer file1.ref.unref();
            file2 = try krn.fs.File.pseudo(inode2);
            errdefer file2.ref.unref();
            try krn.task.current.files.setFD(fd1, file1);
            try krn.task.current.files.setFD(fd2, file2);
            usockvec[0] = @intCast(fd1);
            usockvec[1] = @intCast(fd2);
        } else {
            sock_a.delete();
            return errors.ENOMEM;
        }
    } else {
        return errors.ENOMEM;
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
) !u32 {
    _ = addr;
    _ = addr_len;
    _ = flags;
    if (ubuff == null) {
        return errors.EFAULT;
    }
    if (krn.task.current.files.fds.get(@intCast(fd))) |file| {
        return try krn.socket.do_recvfrom(file, @ptrCast(ubuff), size);
    } else {
        return errors.EBADF;
    }
    return 0;
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
    if (krn.task.current.files.fds.get(@intCast(fd))) |file| {
        return try krn.socket.do_sendto(file, @ptrCast(buff), len);
    } else {
        return errors.EBADF;
    }
    return 0;
}
