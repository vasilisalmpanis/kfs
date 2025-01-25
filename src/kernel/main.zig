const eql = @import("std").mem.eql;
const TTY = @import("drivers").tty.TTY;
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const paging = @import("arch").paging;
const screen = @import("drivers").screen;
const debug = @import("drivers").debug;
const printf = @import("drivers").printf;
const mm = @import("arch").mm;
const vmm = @import("arch").vmm;

fn print_mmap(info: *multiboot.multiboot_info) void {
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
    const scrn: *screen.Screen = screen.Screen.init();
    var mem = mm.mm_init(boot_info);
    var virt: vmm.VMM = vmm.VMM.init(&mem);
    _ = mem.alloc_page();
    _ = mem.alloc_page();
    _ = mem.alloc_page();
    _ = mem.alloc_page();
    _ = mem.alloc_page();
    virt.map_page(0xdd000000, mem.alloc_page());
    // var i : u32 = 0;
    // while (i < 342) : (i += 1) {
    //     const addr = mem.alloc_page();
    //     printf("allocated page: {x}\n", .{addr});
    //     const addr2 = mem.alloc_page();
    //     printf("allocated page: {x}\n", .{addr2});
    //     const addr3 = mem.alloc_page();
    //     printf("allocated page: {x}\n", .{addr3});
    //     printf("freed page: {x}\n", .{addr});
    //     mem.free_page(addr);    
    // }
    var keyboard = Keyboard.init();

    while (true) {
        const input = keyboard.get_input();
        switch (input[0]) {
            'R' => system.reboot(),
            'M' => screen.current_tty.?.move(input[1]),
            'S' => debug.TraceStackTrace(10),
            'C' => screen.current_tty.?.clear(),
            'T' => scrn.switch_tty(input[1]),
            'I' => print_mmap(boot_info),
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, null, true)
        }
    }
}


