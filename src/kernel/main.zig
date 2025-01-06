const TTY = @import("tty.zig");
const interrupts = @import("./interrupts.zig");
const gdt = @import("gdt.zig");
const kbd = @import("drivers").kbd;
const io = @import("arch").io;
const system = @import("arch").system;


export fn kernel_main() noreturn {
    var tty = TTY.TTY.init(80, 25);
    var color: u8 = TTY.vga_entry_color(TTY.ConsoleColors.Red, TTY.ConsoleColors.Black);
    TTY.current_tty = &tty;
    // tty.print("42\nsecond line\n\t\tjust some tabs\nnewlines!!!!\n\n\n\n.\n", color);
    // color = TTY.vga_entry_color(TTY.ConsoleColors.Blue, TTY.ConsoleColors.Black);
    // tty.print("42\nsecond line\n\t\tjust some tabs\nnewlines!!!!\n\n\n\n.\n", color);
    // tty.print("42\nsecond line\n\t\tjust some tabs\nnewlines!!!!\n\n\n\n.\n", null);
    // tty.print("1\n2\n3\n4\n5\n6\n7\n8\n9", null);
    // inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
    //     const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
    //     tty.print("Hello World in all the colors\n", clr);
    // }
    // const one_plus_one: i32 = 1 + 1;
    // const string = "this is a string";
    // TTY.printf("Hello World! {d} {s}\n", .{ one_plus_one, string });
    // tty._x = 0;
    // tty._y -= 1;
    // tty.print("test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test test ", null);
    color = TTY.vga_entry_color(TTY.ConsoleColors.Blue, TTY.ConsoleColors.Black);
    tty.print("STARTING..\n", color);
    // gdt.init_gdt();
    // tty.print("GDT INITIALIZED..\n", color);
    // interrupts.idt_init();
    // tty.print("IDT INITIALIZED..\n", color);
    // TTY.printf("keycode {}\n", .{byte});
    var last_scancode: u8 = 0;
    var key_pressed: bool = false;

    while (true) {
        const byte: u8 = io.inb(0x60);

        if (byte != last_scancode) {
            const key: []const u8 = kbd.scancode_to_key(byte);
            if (key.len != 0) {
                if (byte == 0x0E) {
                    TTY.current_tty.?.remove();
                } else if ( byte == 0x3A) { // CAPSLOCK to reboot (random number)
                    system.reboot();
                } else TTY.printf("{s}", .{key});
            }
            key_pressed = true;
        } else if (key_pressed) {
            key_pressed = false;
        }

        last_scancode = byte;
    }
}
