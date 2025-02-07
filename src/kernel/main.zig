const TTY = @import("drivers").tty.TTY;
const Keyboard = @import("drivers").Keyboard;
const framebuffer = @import("drivers").framebuffer;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const screen = @import("drivers").screen;
pub const mm = @import("mm/init.zig");
const kmlc = @import("mm/kmalloc.zig");
const vmm = @import("arch").vmm;
const dbg = @import("debug");
const builtin = @import("std").builtin;
// const panic = @import("./panic.zig").panic;

fn print_42_colors() void {
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        screen.current_tty.?.print("42\n", clr, false);
    }
}

pub fn panic(msg: []const u8, stack: ?*builtin.StackTrace, size: ?usize) noreturn {
    dbg.printf("PANIC: {s}\nsize {?}\nstack: {?}\n", .{msg, size, stack});
    dbg.TraceStackTrace(20);
    while (true) {}
}

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    const boot_info: *multiboot.multiboot_info = @ptrFromInt(address);
    gdt.gdt_init();
    mm.mm_init(boot_info);
    var scrn: screen.Screen = screen.Screen.init(boot_info);
    screen.current_tty = &scrn.tty[0];
    var keyboard = Keyboard.init();
    while (true) {
        const input = keyboard.get_input();
        switch (input[0]) {
            'R' => system.reboot(),
            'M' => screen.current_tty.?.move(input[1]),
            'S' => dbg.TraceStackTrace(10),
            'C' => screen.current_tty.?.clear(),
            'T' => scrn.switch_tty(input[1]),
            'I' => {
                // dbg.print_mmap(boot_info);
                dbg.walkPageTables();
            },
            'D' => dbg.run_tests(),
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, true),
        }
    }
    panic();
}
