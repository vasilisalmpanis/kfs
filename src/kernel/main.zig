const TTY = @import("tty.zig");
const kbd = @import("drivers").kbd;
const io = @import("arch").io;
const system = @import("arch").system;
const screen = @import("screen.zig");
const debug = @import("debug.zig");


pub fn trace() void {
    debug.TraceStackTrace(10);
}

export fn kernel_main() noreturn {
    var scrn : *screen.Screen = screen.Screen.init();
    // screen.current_tty = &scrn.tty[0];
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        screen.current_tty.?.print("42\n", clr);
    }
    var last_scancode: u8 = 0;
    var key_pressed: bool = false;


    while (true) {
        const byte: u8 = io.inb(0x60);

        if (byte != last_scancode) {
            const key: []const u8 = kbd.scancode_to_key(byte);
            if (key.len != 0) {
                if (byte == 0x0E) { // backspace to erase current entry
                    screen.current_tty.?.remove();
                } else if ( byte == 0x3A) { // CAPSLOCK to reboot (random number)
                    system.reboot();
                } else if (byte == 0x1D) {
                    screen.current_tty.?.move(byte);
                } else if (byte >= 0x01 and byte < 0x0A) { // Numbers from 0 to 1 to change tty
                    scrn.switch_tty(byte - 2);
                } else if (byte == 0x2A) { // Left Shift to print Stack trace
                    trace();
                } else if (byte == 0x38) { // Left Alt to clear the screen
                    screen.current_tty.?.clear();
                } else screen.current_tty.?.print(key, null);
            }
            key_pressed = true;
        } else if (key_pressed) {
            key_pressed = false;
        }

        last_scancode = byte;
    }
}
