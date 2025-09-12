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
        if (krn.task.current.files.fds.get(new_fd)) |old_file| {
            old_file.ops.close(old_file);
        }
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
        try krn.task.current.files.setFD(new_fd, file);
        return new_fd;
    }
    return errors.EBADF;
}
