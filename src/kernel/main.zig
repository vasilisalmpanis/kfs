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

extern var initial_page_dir: [1024]u32;

pub fn trace() void {
    debug.TraceStackTrace(10);
}

// export fn kernel_main() noreturn {
export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    const info: *multiboot.multiboot_info = @ptrFromInt(address);
    gdt.gdt_init();
    const res = mm.mm_init(info);
    _ = res;
    const scrn: *screen.Screen = screen.Screen.init();
    if ((mm.curr_frame & 0xfff) > 0)
        printf("Not boundary aligned", .{});
    printf("current frame {x}", .{mm.curr_frame});
    // var i: u32 = 0;
    // while (i < info.mmap_length) : (i += @sizeOf(multiboot.multiboot_memory_map)) {
    //     const mmap: *multiboot.multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
    //     if (mmap.type == 1)
    //         printf("|{}|\n", .{mmap});
    // }
    // printf("result of mm: {} {}\n", .{res, mm.TOTAL_FRAMES});
    // printf("Paging is enabled\n", .{});
    // inline for (@typeInfo(TTY.ConsoleColors).Enum.fields) |f| {
    //     const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
    //     screen.current_tty.?.print("42\n", clr, false);
    // }

    // Verify multiboot magic number
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
