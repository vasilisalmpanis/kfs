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
const mm = @import("arch").mm;

fn print_mmap(info: *multiboot.multiboot_info, mem: mm.mm) void {
    printf("RAM available: {d}\n", .{mem.avail});
    var i: u32 = 0;
    printf("type\tmem region\t\tsize\n", .{});
    while (i < info.mmap_length) : (i += @sizeOf(multiboot.multiboot_memory_map)) {
        const mmap: *multiboot.multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        printf(
            "{d}\t{x:0>8} {x:0>8}\t{d}\n", .{
                mmap.type,
                mmap.addr[0],
                mmap.addr[0] + (mmap.len[0] - 1),
                mmap.len[0]
        });
    }
}

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
    const mem = mm.mm_init(boot_info);

    const scrn: *screen.Screen = screen.Screen.init();
    var keyboard = Keyboard.init();

    printf("{x} {x} {d} {d}\n", .{mem.base, mem.base + mem.avail, mem.avail, (1 << 10) * 4096});
    while (true) {
        const input = keyboard.get_input();
        switch (input[0]) {
            'R' => system.reboot(),
            'M' => screen.current_tty.?.move(input[1]),
            'S' => debug.TraceStackTrace(10),
            'C' => screen.current_tty.?.clear(),
            'T' => scrn.switch_tty(input[1]),
            'I' => print_mmap(boot_info, mem),
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, null, true)
        }
    }
}


