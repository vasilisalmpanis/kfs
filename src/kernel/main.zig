const eql = @import("std").mem.eql;
const TTY = @import("tty.zig");
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const screen = @import("screen.zig");
const debug = @import("debug.zig");
const printf = @import("printf.zig").printf;


pub fn trace() void {
    debug.TraceStackTrace(10);
}

export fn kernel_main() noreturn {
    gdt.gdt_init();
    var scrn : *screen.Screen = screen.Screen.init();
    // printf("GDT INITIALIZED\n", .{});
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        screen.current_tty.?.print("42\n", clr, false);
    }
    printf("\n", .{});
    var keyboard = Keyboard.init();

    while (true) {
        const input = keyboard.get_input();
        switch (input[0]) {
            'R' => system.reboot(),
            'M' => screen.current_tty.?.move(input[1]),
            'S' => trace(),
            'C' => screen.current_tty.?.clear(),
            'T' => scrn.switch_tty(input[1]),
            else => if (input[1] != 0) printf("{c}",.{input[1]})
        }
    }
}
