const types = @import("types");
const std = @import("std");

pub fn panic(
    msg: []const u8,
    _: ?*std.builtin.StackTrace,
    _: ?usize
) noreturn {
    types.api.module_panic(msg.ptr, msg.len);
    while (true) {}
}

export fn example_init() linksection(".init") callconv(.c) u32 {
    types.dbg.printf("Loading example module\n", .{});
    return 0;
}

export fn example_exit() linksection(".exit") callconv(.c) void {
    types.dbg.printf("Unloading example module\n", .{});
}
