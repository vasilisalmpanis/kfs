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
    const user_path = std.mem.span(path_name.?);
    krn.logger.INFO("mkdir {s}\n", .{user_path});
    const stripped_path = fs.path.remove_trailing_slashes(user_path);
    var dir_name: []const u8 = "";
    const parent = fs.path.dir_resolve(stripped_path, &dir_name) catch |err| {
        return err;
    };
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
