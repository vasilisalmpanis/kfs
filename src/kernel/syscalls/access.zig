const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

const F_OK: i32 = 0;
const X_OK: i32 = 1;
const W_OK: i32 = 2;
const R_OK: i32 = 4;

pub fn do_access(path: []const u8, mode: i32) !u32 {
    const resolved_path = try kernel.fs.path.resolve(path);
    defer resolved_path.release();

    const inode = resolved_path.dentry.inode;

    const real_uid: u32 = kernel.task.current.uid;
    const real_gid: u32 = kernel.task.current.gid;

    if (mode < 0 or mode > (F_OK | R_OK | W_OK | X_OK)) {
        return errors.EINVAL;
    }

    if (mode == F_OK) {
        return 0;
    }

    if ((mode & R_OK) != 0) {
        if (!inode.mode.canRead(real_uid, real_gid)) {
            return errors.EACCES;
        }
    }

    if ((mode & W_OK) != 0) {
        if (!inode.mode.canWrite(real_uid, real_gid)) {
            return errors.EACCES;
        }
    }

    if ((mode & X_OK) != 0) {
        if (!inode.mode.canExecute(real_uid, real_gid)) {
            return errors.EACCES;
        }
    }

    return 0;
}

pub fn access(path: ?[*:0]const u8, mode: i32) !u32 {
    if (path == null)
        return errors.EINVAL;
    const path_span = std.mem.span(path.?);
    return do_access(path_span, mode);
}
