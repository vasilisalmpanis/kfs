const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const kernel = @import("../main.zig");
const fs = kernel.fs;
const std = @import("std");

pub fn time(t: u32, _: u32, _: u32, _: u32, _: u32, _: u32) !u32 {
    const current_time: u32 = 0; // TODO: Implement proper time tracking
    
    if (t != 0) {
        const time_ptr: *u32 = @ptrFromInt(t);
        time_ptr.* = current_time;
    }
    
    return current_time;
}

pub fn utimensat(
    dirfd: i32,
    _path: ?[*:0] const u8,
    _times: ?*[2]kernel.kernel_timespec,
    flags: u32,
) !u32 {
    _ = flags;
    const path = _path orelse
        return errors.EINVAL;
    const times = _times orelse
        return errors.EACCES;
    if (!times[0].isValid())
        return errors.EINVAL;
    if (!times[1].isValid())
        return errors.EINVAL;
    const span = std.mem.span(path);
    var from = kernel.task.current.fs.pwd.clone();
    defer from.release();
    if (!fs.path.isRelative(span)) {
    } else if (dirfd < 0 and dirfd != fs.AT_FDCWD) {
        return errors.EINVAL;
    } else if (dirfd == fs.AT_FDCWD) {
    } else {
        from.release();
        if (kernel.task.current.files.fds.get(@intCast(dirfd))) |file| {
            if (file.path) |file_path| {
                from = file_path.clone();
            }
        }
        return errors.EBADF;
    }
    const target = try fs.path.resolveFrom(path, from, true);
    defer target.release();
    if (target.dentry.inode.ops.setattr) |_setattr| {
        const attr = fs.InodeAttrs{
            .atime = times[0],
            .mtime = times[1],
        };
        _setattr(target.dentry.inode, &attr);
        return 0;
    }
    return errors.EROFS;
}
