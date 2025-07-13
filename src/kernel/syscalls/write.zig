const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn write(fd: u32, buf: u32, size: u32) !u32 {
    const data: [*]u8 = @ptrFromInt(buf);
    if (fd == 2) {
        krn.serial.print(data[0..size]);
    } else {
        dbg.printf("{s}", .{data[0..size]});
    }
    return @intCast(size);
}
