const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");

pub fn dup2(old_fd: u32, new_fd: u32) !u32 {
    if (krn.task.current.files.fds.get(old_fd)) |file| {
        if (old_fd == new_fd) {
            return new_fd;
        }
        if (krn.task.current.files.fds.get(new_fd)) |_| {
            _ = krn.task.current.files.releaseFD(new_fd);
        }
        file.ref.ref();
        try krn.task.current.files.setFD(new_fd, file);
        return new_fd;
    }
    return errors.EBADF;
}

pub fn dup(old_fd: u32) !u32 {
    if (krn.task.current.files.fds.get(old_fd)) |file| {
        const new_fd = krn.task.current.files.getNextFD() catch |err| {
            krn.logger.ERROR("dup: failed to get next fd: {any}", .{err});
            return errors.EMFILE;
        };
        file.ref.ref();
        try krn.task.current.files.setFD(new_fd, file);
        return new_fd;
    }
    return errors.EBADF;
}

const F_DUPFD		= 0x0;	// dup
const F_GETFD		= 0x1;	// get close_on_exec
const F_SETFD		= 0x2;	// set/clear close_on_exec
const F_GETFL		= 0x3;	// get file->f_flags
const F_SETFL		= 0x4;	// set file->f_flags
const F_GETLK		= 0x5;
const F_SETLK		= 0x6;
const F_SETLKW	= 0x7;

const F_SETLEASE	= 0x400;
const F_GETLEASE	= 0x401;
const F_NOTIFY	= 0x402;
const F_DUPFD_QUERY	= 0x403;

const F_CANCELLK	= 0x405;
const F_DUPFD_CLOEXEC	= 0x406;

pub fn fcntl64(fd: u32, cmd: u32, arg: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        krn.logger.DEBUG(
            "fcntl64 {d}: {s}, cmd 0x{x}, arg 0x{x}", 
            .{fd, file.path.?.dentry.name, cmd, arg}
        );
        switch (cmd) {
            F_DUPFD => {
                const new_fd = try krn.task.current.files.getNextFromFD(arg);
                return try dup2(fd, new_fd);
            },
            F_GETFD => {
                return 0; // close_on_exec not supported
            },
            F_SETFD => {
                return 0; // close_on_exec not supported
            },
            F_GETFL => {
                return @intCast(file.flags);
            },
            F_SETFL => {
                file.flags = @intCast(arg);
                return 0;
            },
            F_DUPFD_CLOEXEC => {
                const new_fd = try krn.task.current.files.getNextFromFD(arg);
                return try dup2(fd, new_fd);
            },
            else => return errors.EINVAL,
        }
    }
    krn.logger.ERROR("fcntl64 bad fd {d}", .{fd});
    return errors.EBADF;
}
