const TTY = @import("tty.zig");
const interrupts = @import("./interrupts.zig");

export fn kernel_main() noreturn {
    interrupts.idt_init();
    var tty = TTY.TTY.init(80, 25);
    var color: u8 = TTY.vga_entry_color(TTY.ConsoleColors.Red, TTY.ConsoleColors.Black);
    TTY.current_tty = &tty;
    tty.print("42\nsecond line\n\t\tjust some tabs\nnewlines!!!!\n\n\n\n.\n", color);
    color = TTY.vga_entry_color(TTY.ConsoleColors.Blue, TTY.ConsoleColors.Black);
    tty.print("42\nsecond line\n\t\tjust some tabs\nnewlines!!!!\n\n\n\n.\n", color);
    tty.print("42\nsecond line\n\t\tjust some tabs\nnewlines!!!!\n\n\n\n.\n", null);
    tty.print("1\n2\n3\n4\n5\n6\n7\n8\n9", null);
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        tty.print("Hello World in all the colors\n", clr);
    }
    const one_plus_one: i32 = 1 + 1;
    const string = "this is a string";
    TTY.printf("Hello World! {d} {s}\n", .{ one_plus_one, string });
    tty._x = 0;
    tty._y -= 1;
    tty.print("test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test ", null);
    while (true) {}
}
