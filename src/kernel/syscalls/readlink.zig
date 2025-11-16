const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");

pub fn readlink(_path: ?[*:0]u8, _buf: ?[*]u8, size: isize) !u32 {
    if (size < 0)
        return errors.EINVAL;
    const path = _path orelse {
        return errors.EINVAL;
    };
    const buf = _buf orelse {
        return errors.EINVAL;
    };

    const path_span = std.mem.span(path);
    var last_segment: []const u8 = "";
    const parent = try fs.path.dir_resolve(path_span, &last_segment);
    defer parent.release();
    if (last_segment.len == 0) {
        return errors.EINVAL;
    }

    const target_dentry =  try parent.dentry.inode.ops.lookup(parent.dentry, last_segment);
    if (!target_dentry.inode.mode.isLink())
        return errors.EINVAL;
    if (target_dentry.inode.ops.readlink) |_readlink| {
        return try _readlink(target_dentry.inode, buf, @intCast(size));
    }
    return errors.ENOSYS;
}
