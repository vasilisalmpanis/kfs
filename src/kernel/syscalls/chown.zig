const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

pub fn do_chown(
    fd: i32,
    path: []const u8,
    uid: u32,
    gid: u32,
    flags: u32
) !u32 {
    _ = flags;
    var from = kernel.task.current.fs.pwd.clone();
    defer from.release();
    if (!fs.path.isRelative(path)) {
    } else if (fd < 0 and fd != fs.AT_FDCWD) {
        return errors.EINVAL;
    } else if (fd == fs.AT_FDCWD) {
    } else {
        from.release();
        if (kernel.task.current.files.fds.get(@intCast(fd))) |file| {
            if (file.path) |_path| {
                from = _path.clone();
            }
        }
        return errors.ENOENT;
    }
    const target = try fs.path.resolveFrom(path, from, true);
    defer target.release();

    if (target.dentry.inode.ops.setattr) |_setattr| {
        const attr = fs.InodeAttrs{
            .uid = uid,
            .gid = gid,
        };
        try _setattr(target.dentry.inode, &attr);
        return 0;
    }
    return errors.EINVAL;
}

pub fn chown32(_path: ?[*:0] const u8, uid: u32, gid: u32) !u32 {
    const path = _path orelse
        return errors.EINVAL;
    const span: [:0]const u8 = std.mem.span(path);
    return try do_chown(fs.AT_FDCWD, span, uid, gid, fs.AT_SYMLINK_FOLLOW);
}

pub fn lchown(_path: ?[*:0] const u8, uid: u32, gid: u32) !u32 {
    const path = _path orelse
        return errors.EINVAL;
    const span: [:0]const u8 = std.mem.span(path);
    return try do_chown(fs.AT_FDCWD, span, uid, gid, fs.AT_SYMLINK_NOFOLLOW);
}

pub fn fchownat(
    fd: i32,
    _path: ?[*:0] const u8,
    uid: u32,
    gid: u32,
    flags: u32,
) !u32 {
    const path = _path orelse
        return errors.EINVAL;
    const span: [:0]const u8 = std.mem.span(path);
    return try do_chown(fd, span, uid, gid, flags);
}
