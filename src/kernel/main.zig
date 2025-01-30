const TTY = @import("drivers").tty.TTY;
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const screen = @import("drivers").screen;
pub const mm = @import("mm/init.zig");
const vmm = @import("arch").vmm;
const dbg = @import("debug");

fn print_42_colors() void {
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        screen.current_tty.?.print("42\n", clr, false);
    }
}

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    const boot_info: *multiboot.multiboot_info = @ptrFromInt(address);
    gdt.gdt_init();
    const scrn: *screen.Screen = screen.Screen.init();
    mm.mm_init(boot_info);
    // Initialize heap or not
    // Understand where we want to map out heap ex 0F0000000 - 0xE0000000
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
                dbg.print_page_dir();
            },
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, null, true),
        }
    }
}
