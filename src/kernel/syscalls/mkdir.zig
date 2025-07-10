const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig");

pub fn mkdir(
    path_name: ?[*:0]u8,
    mode: u16,
) i32 {
    if (path_name == null) {
        return -errors.ENOENT;
    }
    const user_path = std.mem.span(path_name.?);
    const stripped_path = fs.path.remove_trailing_slashes(user_path);
    var dir_name: []const u8 = undefined;
    const parent = fs.path.dir_resolve(stripped_path, &dir_name) catch {
        return -errors.ENOTDIR;
    };
    var dir_mode: fs.UMode = @bitCast(mode);
    dir_mode.type = fs.S_IFDIR;
    _ = parent.inode.ops.mkdir(
        parent.inode,
        parent,
        dir_name,
        dir_mode
    ) catch {
        return -errors.ENOENT;
    };
    return 0;
}
