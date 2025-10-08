const kernel = @import("kernel");
const debug = @import("debug");

pub fn print_screen(arr: [*]const u8, size: u32) callconv(.c) void {
   // debug.printf(arr[0..size], .{});
   kernel.screen.current_tty.?.print(arr[0..size]);
}

pub fn print_serial(arr: [*]const u8, size: u32) callconv(.c) void {
    kernel.serial.print(arr[0..size]);
}
