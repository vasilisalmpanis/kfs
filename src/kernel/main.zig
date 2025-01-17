const eql = @import("std").mem.eql;
const TTY = @import("tty.zig");
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const paging = @import("arch").paging;
const screen = @import("screen.zig");
const debug = @import("debug.zig");
const printf = @import("printf.zig").printf;

extern var initial_page_dir: [1024]u32;

pub fn trace() void {
    debug.TraceStackTrace(10);
}

// export fn kernel_main() noreturn {
export fn kernel_main(magic: u32, address: u32) noreturn {
    gdt.gdt_init();
    const scrn: *screen.Screen = screen.Screen.init();
    printf("Paging is enabled\n", .{});
    inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        screen.current_tty.?.print("42\n", clr, false);
    }

    // Verify multiboot magic number
    if (magic != 0x2BADB002) {
        printf("Invalid multiboot magic number!\n", .{});
        while (true) {}
    }

    const info: *multiboot.multiboot_info = @ptrFromInt(address);
    var i: u32 = 0;
    while (i < info.mmap_length) : (i += @sizeOf(multiboot.multiboot_memory_map)) {
        const mmap: *multiboot.multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        _ = mmap;
        // printf("mmap {}\n", .{mmap});
    }
    var keyboard = Keyboard.init();

    while (true) {
        const input = keyboard.get_input();
        switch (input[0]) {
            'R' => system.reboot(),
            'M' => screen.current_tty.?.move(input[1]),
            'S' => trace(),
            'C' => screen.current_tty.?.clear(),
            'T' => scrn.switch_tty(input[1]),
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, null, true)
        }
    }
}
