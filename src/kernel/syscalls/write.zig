const errors = @import("../main.zig").errors;
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn write(_: *arch.cpu.Regs, fd: u32, buf: u32, size: u32) i32 {
    const data: [*]u8 = @ptrFromInt(buf);
    if (fd == 2) {
        krn.serial.print(data[0..size]);
    } else {
        dbg.printf("{s}", .{data[0..size]});
    }
    return @intCast(size);
}
