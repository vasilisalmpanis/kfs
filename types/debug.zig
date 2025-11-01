const types = @import("types.zig");
const mm = @import("mm.zig");
const std = @import("std");

pub extern const keymap_us: *const std.EnumMap(types.drivers.keyboard.ScanCode, types.drivers.keyboard.KeymapEntry);
pub extern const keymap_de: *const std.EnumMap(types.drivers.keyboard.ScanCode, types.drivers.keyboard.KeymapEntry);

pub extern var global_keyboard: *types.drivers.Keyboard;

pub extern fn print_serial(arr: [*]const u8, size: u32) callconv(.c) void;

pub fn printf(comptime format: []const u8, args: anytype) void {
    const size = std.fmt.count(format, args);
    if (mm.kmallocSlice(u8, size)) |slice| {
        defer mm.kfree(slice.ptr);
        _ = std.fmt.bufPrint(slice, format, args) catch { return; };
        types.api.printf(slice.ptr, slice.len);
    }
}
