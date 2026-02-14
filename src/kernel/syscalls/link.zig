const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

fn do_link(
    link_parent_dir: fs.path.Path,
    link_name: []const u8,
    target: fs.path.Path,
) !u32 {
    const parent_inode = link_parent_dir.dentry.inode;
    if (parent_inode.ops.link) |_link| {
        _ = try _link(link_parent_dir.dentry, link_name, target);
        return 0;
    }
    return errors.EPERM;
}

pub fn link(target: ?[*:0]u8, linkpath: ?[*:0]u8) !u32 {
    if (target == null or linkpath == null)
        return errors.EFAULT;
    const _target: [:0]const u8 = std.mem.span(target.?);
    const _linkpath: [:0]const u8 = std.mem.span(linkpath.?);
    if (_linkpath.len == 0 or _target.len == 0)
        return errors.ENOENT;
    var link_name: []const u8 = "";
    const link_parent_dir = try fs.path.dir_resolve(_linkpath, &link_name);
    defer link_parent_dir.release();
    const parent_inode = link_parent_dir.dentry.inode;
    if (!parent_inode.mode.canWrite(parent_inode.uid, parent_inode.gid))
        return errors.EACCES;
    if (link_name.len == 0)
        return errors.EEXIST;
    const target_path = try fs.path.resolve(_target);
    defer target_path.release();
    if (target_path.dentry.inode.mode.isDir()) {
        return errors.EPERM;
    }
    if (target_path.mnt != link_parent_dir.mnt) {
        return errors.EXDEV;
    }
    _ = parent_inode.ops.lookup(link_parent_dir.dentry, link_name) catch |err| {
        switch (err) {
            errors.ENOENT => {
                return do_link(link_parent_dir, link_name, target_path);
            },
            else => return err,
        }
    };
    return errors.EEXIST;
}
