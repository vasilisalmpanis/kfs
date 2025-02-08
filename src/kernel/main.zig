const TTY = @import("drivers").tty.TTY;
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const screen = @import("drivers").screen;
pub const mm = @import("mm/init.zig");
const dbg = @import("debug");
const builtin = @import("std").builtin;
const idt = @import("arch").idt;

pub fn panic(
    msg: []const u8,
    stack: ?*builtin.StackTrace,
    first_trace_addr: ?usize
) noreturn {
    dbg.printf(
        "\nPANIC: {s}\nfirst_trace_addr {?}\nstack: {?}\n",
        .{msg, first_trace_addr, stack}
    );
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
    idt.idt_init();
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
                dbg.print_mmap(boot_info);
                dbg.walkPageTables();
            },
            'D' => dbg.run_tests(),
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, true),
        }
    }
    panic("You shouldn't be here");
}
