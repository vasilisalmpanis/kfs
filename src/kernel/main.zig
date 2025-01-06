const TTY = @import("tty.zig");
const interrupts = @import("./interrupts.zig");
const gdt = @import("gdt.zig");
const kbd = @import("drivers").kbd;
const io = @import("arch").io;
const system = @import("arch").system;
const screen = @import("screen.zig");


export fn kernel_main() noreturn {
    var scrn : screen.Screen = screen.Screen.init();
    _ = &scrn;
    TTY.current_tty = &scrn.tty[0];
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        TTY.current_tty.?.print("42\n", clr);
    }
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
                } else if (byte == 0x1D) {
                    TTY.current_tty.?.move(byte);
                } else if (byte >= 0x01 and byte < 0x0A) {
                    TTY.current_tty = &scrn.tty[byte - 2];
                    TTY.current_tty.?.render();
                } else TTY.current_tty.?.print(key, null);
            }
            key_pressed = true;
        } else if (key_pressed) {
            key_pressed = false;
        }

        last_scancode = byte;
    }
}
