const errors = @import("../main.zig").errors;
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn write(_: *arch.cpu.Regs, fd: u32, buf: u32, size: u32) i32 {
    _ = fd;
    const data: [*]u8 = @ptrFromInt(buf);
    dbg.printf("{s}", .{data[0..size]});
    return 0;
}
