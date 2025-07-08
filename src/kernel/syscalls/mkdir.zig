const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig");

pub fn mkdir(
    path_name: ?[*]u8,
    mode: u32,
) i32 {
    if (path_name == null) {
        return -errors.ENOENT;
    }
    const user_path = std.mem.span(path_name);
    const stripped_path = fs.path.remove_trailing_slashes(user_path);
    const parent = fs.path.dir_resolve(stripped_path) catch |err| {
        _ = err;
        return -errors.ENOTDIR;
    };
    // TODO we need to pass segment to mkdir and not the full path.
    parent.inode.ops.mkdir(parent.inode, parent, stripped_path, mode);
    return 0;
}
