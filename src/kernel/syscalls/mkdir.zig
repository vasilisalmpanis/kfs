const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig").PosixError;
const drv = @import("drivers");

pub fn mkdir(
    path_name: ?[*:0]const u8,
    mode: u16,
) !u32 {
    if (path_name == null) {
        return errors.ENOENT;
    }
    const user_path: [:0]const u8 = std.mem.span(path_name.?);
    krn.logger.INFO("mkdir {s}\n", .{user_path});
    const stripped_path = fs.path.remove_trailing_slashes(user_path);
    var dir_name: []const u8 = "";
    const parent = fs.path.dir_resolve(stripped_path, &dir_name) catch |err| {
        return err;
    };
    defer parent.release();
    if (dir_name.len == 0)
        return errors.EEXIST;
    if (
        !parent.dentry.inode.mode.canExecute(
            parent.dentry.inode.uid,
            parent.dentry.inode.gid
        )
        or !parent.dentry.inode.mode.canWrite(
            parent.dentry.inode.uid,
            parent.dentry.inode.gid
        )
    ) {
        return errors.EACCES;
    }
    var dir_mode: fs.UMode = @bitCast(mode);
    dir_mode.type = fs.S_IFDIR;
    _ = parent.dentry.inode.ops.mkdir(
        parent.dentry.inode,
        parent.dentry,
        dir_name,
        dir_mode
    ) catch |err| {
        return err;
    };
    return 0;
}

pub fn do_rmdir_at(path: []const u8, from: krn.fs.path.Path) !u32 {
    var name: []const u8 = "";
    const parent = try krn.fs.path.dir_resolve_from(path, from, &name);
    defer parent.release();
    const parent_ino = parent.dentry.inode;
    if (!parent_ino.mode.canWrite(parent_ino.uid, parent_ino.gid))
        return errors.EACCES;
    if (name.len == 0)
        return errors.ENOENT;
    const to_remove = try parent.dentry.inode.ops.lookup(parent.dentry, name);
    if (!to_remove.inode.mode.isDir())
        return errors.ENOTDIR;
    if (parent.dentry.inode.ops.rmdir) |_rmdir| {
        try _rmdir(to_remove, parent.dentry);
        return 0;
    }
    return errors.EPERM;
}

pub fn rmdir(path: ?[*:0]u8) !u32 {
    const _path: [:0]const u8 = if (path) |p|
        std.mem.span(p)
    else
        return errors.EFAULT;

    const from = krn.task.current.fs.pwd.clone();
    defer from.release();
    return do_rmdir_at(_path, from);
}
