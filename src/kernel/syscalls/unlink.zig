const krn = @import("../main.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig").PosixError;

const AT_REMOVEDIR = 0x200; // Remove directory

fn do_unlinkat(dirfd: i32, _path: ?[*:0]u8) !u32 {
    if (dirfd < 0 and dirfd != fs.AT_FDCWD)
        return errors.EINVAL;
    const path = _path orelse
        return errors.EINVAL;
    const path_span = std.mem.span(path);
    var from: fs.path.Path = undefined;
    if (!fs.path.isRelative(path_span)) {
        from = krn.task.current.fs.pwd.clone();
    } else if (dirfd == fs.AT_FDCWD) {
        from = krn.task.current.fs.pwd.clone();
    } else if (krn.task.current.files.fds.get(@intCast(dirfd))) |file| {
        if (file.path) |file_path| {
            from = file_path.clone();
            errdefer from.release();
            if (!from.dentry.inode.mode.isDir())
                return errors.ENOTDIR;
        } else {
            return errors.EBADF;
        }
    } else {
        return errors.EBADF;
    }
    defer from.release();
    var last_segment: []const u8 = "";
    const parent = try fs.path.dir_resolve_from(path_span, from, &last_segment);
    defer parent.release();
    if (last_segment.len == 0)
        return errors.EISDIR;
    if (!parent.dentry.inode.mode.canWrite(parent.dentry.inode.uid, parent.dentry.inode.gid)) {
        return errors.EPERM;
    }
    const target = try parent.dentry.inode.ops.lookup(parent.dentry, last_segment);
    if (target.inode.mode.isDir()) {
        return errors.EISDIR;
    }

    if (from.dentry.inode.ops.unlink) |_unlink| {
        // Dentry handling
        const key = fs.DentryHash{
            .name = last_segment,
            .ino =  parent.dentry.inode.i_no,
            .sb = @intFromPtr(parent.dentry.sb),
        };
        _ = fs.dcache.remove(key);

        try _unlink(parent.dentry.inode, target);

        parent.dentry.ref.unref();
        target.tree.del();
        target.tree.parent = null;
        target.release();
        return 0;
    } else {
        return errors.EPERM;
    }
}

pub fn unlink(path: ?[*:0]u8) !u32 {
    return do_unlinkat(fs.AT_FDCWD, path);
}

pub fn unlinkat(dirfd: i32, path: ?[*:0]u8, flags: i32) !u32 {
    if (flags & ~AT_REMOVEDIR != 0)
        return errors.EINVAL;
    if (flags & AT_REMOVEDIR != 0)
        // TODO rmdir
        return errors.ENOSYS;
    return try do_unlinkat(dirfd, path);
}
