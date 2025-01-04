const vga: [*]u16 = @ptrFromInt(0xb8000);

fn set_color() void {}

export fn kernel_main() noreturn {
    const str = "42";
    var index: u32 = 0;
    for (str) |c| {
        vga[index] = (0x0f << 8) | @as(u16, c);
        index += 1;
    }
    while (true) {}
}
