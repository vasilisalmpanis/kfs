const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

const AT_RENAME_NOREPLACE	        = 0x0001;
const AT_RENAME_EXCHANGE	        = 0x0002;
const AT_RENAME_WHITEOUT	        = 0x0004;

fn resolveat(dirfd: i32, path: []const u8, name: *[]const u8) !kernel.fs.path.Path {
    var from: kernel.fs.path.Path = kernel.task.current.fs.pwd.clone();
    defer from.release();
    if (path[0] == '/') {
    } else if (dirfd < 0 and dirfd != fs.AT_FDCWD) {
        return errors.EBADF;
    } else if (dirfd == fs.AT_FDCWD) {
    } else {
        if (kernel.task.current.files.fds.get(@intCast(dirfd))) |dir| {
            if (!dir.inode.mode.isDir())
                return errors.ENOTDIR;
            if (dir.path == null)
                return errors.EBADF;
            from.release();
            from = dir.path.?.clone();
        } else {
            return errors.EBADF;
        }
    }
    const parent = try fs.path.dir_resolve_from(path, from, name);
    if (!parent.dentry.inode.canWrite())
        return errors.EACCES;
    if (name.len == 0)
        return errors.ENOENT;
    return parent;
}

pub fn renameat2(
    olddirfd: i32, oldpath: ?[*:0]u8,
    newdirfd: i32, newpath: ?[*:0]u8,
    flags: u32
) !u32 {
    _ = flags;
    const _oldpath: []const u8 = if (oldpath) |_p|
        std.mem.span(_p)
    else
        return errors.EFAULT;
    const _newpath: []const u8 = if (newpath) |_p|
        std.mem.span(_p)
    else
        return errors.EFAULT;
    if (_oldpath.len == 0 or _newpath.len == 0)
        return errors.ENOENT;
    var oldname: []const u8 = "";
    var newname: []const u8 = "";
    const old_parent = try resolveat(olddirfd, _oldpath, &oldname);
    defer old_parent.release();
    const new_parent = try resolveat(newdirfd, _newpath, &newname);
    defer new_parent.release();
    const old_path = try fs.path.resolveFrom(oldname, old_parent, true);
    errdefer old_path.release();
    const new_path: ?fs.path.Path = fs.path.resolveFrom(newname, new_parent, true) catch |err| blk: {
        switch (err) {
            errors.ENOENT => break :blk null,
            else => return err,
        }
    };
    if (new_path) |_p| {
        errdefer _p.release();
        if (old_path.dentry.inode.mode.isDir() and !_p.dentry.inode.mode.isDir())
            return errors.ENOTDIR;
        if (old_path.mnt != _p.mnt)
            return errors.EXDEV;
        if (_p.isSubPathOf(&old_path))
            return errors.EINVAL;
        if (_p.dentry.inode == old_path.dentry.inode) {
            old_path.release();
            _p.release();
            return 0;
        }
        if (old_path.dentry.inode.ops.rename) |_rename| {
            old_path.release();
            _p.release();
            try _rename(old_parent.dentry, old_path.dentry, new_parent.dentry, newname);
            return 0;
        }
        return errors.EPERM;
    } else {
        if (old_path.mnt != new_parent.mnt)
            return errors.EXDEV;
        if (new_parent.isSubPathOf(&old_path))
            return errors.EINVAL;
        if (old_path.dentry.inode.ops.rename) |_rename| {
            old_path.release();
            try _rename(old_parent.dentry, old_path.dentry, new_parent.dentry, newname);
            return 0;
        }
        return errors.EPERM;
    }
}

pub fn renameat(
    olddirfd: i32, oldpath: ?[*:0]u8,
    newdirfd: i32, newpath: ?[*:0]u8
) !u32 {
    return try renameat2(
        olddirfd, oldpath,
        newdirfd, newpath,
        0
    );
}

pub fn rename(oldpath: ?[*:0]u8, newpath: ?[*:0]u8) !u32 {
    return try renameat(
        kernel.fs.AT_FDCWD, oldpath,
        kernel.fs.AT_FDCWD, newpath,
    );
}
