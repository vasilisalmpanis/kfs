const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const errors = @import("error-codes.zig").PosixError;
const std = @import("std");
const dbg = @import("debug");

pub fn mount(
    dev_name: ?[]const u8,
    dir_name: ?[]const u8,
    fs_type: ?[*:0]u8,
    new_flags: u32,
    data: ?*anyopaque
) !u32 {
    if (fs_type) |string| { 
        const user_type: []const u8 = std.mem.span(string);
        if (fs.FileSystem.find(user_type)) |_type| {
            _ = fs.Mount.mount(dev_name.?, dir_name.?, _type) catch {
                krn.logger.INFO("Error while mounting \n", .{});
                return errors.ENOENT;
            };
            return 0;
        }
    }
    dbg.printf("Wrong fs type\n", .{});
    _ = new_flags;
    _ = data;
    return errors.ENOENT;
}
