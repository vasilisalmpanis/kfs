const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig").PosixError;
const drv = @import("drivers");

pub fn chdir(path: ?[*:0]const u8) !u32 {
    if (path == null) {
        return errors.ENOENT;
    }
    const user_path = std.mem.span(path.?);
    const p = fs.path.resolve(user_path) catch {
        return errors.ENOENT;
    };
    if (!p.dentry.inode.mode.isDir()) {
        return errors.ENOTDIR;
    }
    krn.task.current.fs.pwd = p;
    return 0;
}

pub fn fchdir(fd: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (!file.inode.mode.isDir()) {
            return errors.ENOTDIR;
        }
        krn.task.current.fs.pwd = file.path;
        return 0;
    }
    return errors.EBADF;
}
