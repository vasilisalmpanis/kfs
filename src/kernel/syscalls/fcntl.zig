const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");
const dup2 = @import("./dup.zig").dup2;


const F_DUPFD		= 0x0;	// dup
const F_GETFD		= 0x1;	// get close_on_exec
const F_SETFD		= 0x2;	// set/clear close_on_exec
const F_GETFL		= 0x3;	// get file flags
const F_SETFL		= 0x4;	// set file flags
const F_GETLK		= 0x5;
const F_SETLK		= 0x6;
const F_SETLKW	= 0x7;

const F_SETLEASE	= 0x400;
const F_GETLEASE	= 0x401;
const F_NOTIFY	= 0x402;
const F_DUPFD_QUERY	= 0x403;

const F_CANCELLK	= 0x405;
const F_DUPFD_CLOEXEC	= 0x406;

const FD_CLOEXEC = 1;

pub fn fcntl(fd: u32, op: i32, arg: u32) !u32 {
    krn.logger.DEBUG("fcntl fd: {d}, op: {d}, arg: {d}", .{fd, op, arg});
    return 0;
}

pub fn fcntl64(fd: u32, cmd: u32, arg: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        krn.logger.DEBUG(
            "fcntl64 {d}: {s}, cmd 0x{x}, arg 0x{x}", 
            .{fd, file.path.?.dentry.name, cmd, arg}
        );
        switch (cmd) {
            F_DUPFD, F_DUPFD_CLOEXEC => {
                const new_fd = try krn.task.current.files.getNextFromFD(arg);
                const dup_fd = try dup2(fd, new_fd);
                if (cmd == F_DUPFD_CLOEXEC)
                    krn.task.current.files.closexec.set(dup_fd);
                return dup_fd;
            },
            F_GETFD => {
                if (krn.task.current.files.closexec.isSet(fd))
                    return FD_CLOEXEC;
                return 0;
            },
            F_SETFD => {
                if (arg & FD_CLOEXEC != 0)
                    krn.task.current.files.closexec.set(fd);
                return 0;
            },
            F_GETFL => {
                return @intCast(file.flags);
            },
            F_SETFL => {
                file.flags = @intCast(arg);
                return 0;
            },
            else => return errors.EINVAL,
        }
    }
    krn.logger.ERROR("fcntl64 bad fd {d}", .{fd});
    return errors.EBADF;
}
