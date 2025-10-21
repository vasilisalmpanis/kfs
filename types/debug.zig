const types = @import("types.zig");
const mm = @import("mm.zig");
const std = @import("std");

pub fn print(format: []const u8) void {
    types.api.printf(format.ptr, format.len);
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    const size = std.fmt.count(format, args);
    if (mm.kmallocSlice(u8, size)) |slice| {
        _ = std.fmt.bufPrint(slice, format, args) catch { return; };
        types.api.printf(slice.ptr, slice.len);
    }
}
