const std = @import("std");
const arch = @import("arch");
const krn = @import("../main.zig");

const PT_TYPE = enum (u32) {
    PT_NULL = 0,
    PT_LOAD = 1,
    _,
};

const HeaderFlags = packed struct (u32) {
    exec: bool,
    write: bool,
    read: bool,
    _pad: u29,
};

pub fn goUserspace(userspace: []const u8) void {
    const userspace_offset: u32 = 0x1000;
    var heap_start: u32 = 0;

    krn.mm.virt_memory_manager.mapPage(
        0,
        krn.mm.virt_memory_manager.pmm.allocPage(),
        .{.user = true}
    );
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(userspace));
    const programm_header_size: u32 = ehdr.e_phentsize;
    const programm_header_num: u32 = ehdr.e_phnum;
    for (0..programm_header_num) |i| {
        const program_header: *std.elf.Elf32_Phdr = @ptrCast(@constCast(@alignCast(&userspace[ehdr.e_phoff + (programm_header_size * i)])));
        const header_type: PT_TYPE = @enumFromInt(program_header.p_type);
        if (header_type != PT_TYPE.PT_LOAD) {
            continue;
        }
        const virt_addr = program_header.p_vaddr;
        const flags: HeaderFlags = @bitCast(program_header.p_flags);
        var num_pages = program_header.p_memsz / arch.PAGE_SIZE;
        if (program_header.p_memsz < arch.PAGE_SIZE)
            num_pages = 1;
        const phys = krn.mm.virt_memory_manager.pmm.allocPages(num_pages);
        if (phys == 0)
            @panic("Cannot go to userspace");
        for (0..num_pages) |idx| {
            krn.mm.virt_memory_manager.mapPage(virt_addr + (idx * arch.PAGE_SIZE), phys + (idx * arch.PAGE_SIZE), .{
                .user = true,
            });
        }
        const code_ptr: [*]u8 = @ptrFromInt(program_header.p_vaddr);
        if (flags.write == false) {
            // allocate and memcpy
            @memcpy(code_ptr[0..program_header.p_memsz], userspace[program_header.p_paddr..program_header.p_paddr + program_header.p_memsz]);
        } else {
            // allocate and set to 0
            @memset(code_ptr[0..program_header.p_memsz], 0);
            krn.task.current.mm.?.bss = program_header.p_vaddr;
        }
        if (program_header.p_vaddr + program_header.p_memsz > heap_start)
            heap_start = program_header.p_vaddr + program_header.p_memsz;
    }
    // while (true) {}
    const stack_size: u32 = 40 * 4096;
    const stack_phys: u32 = krn.mm.virt_memory_manager.pmm.allocPages(stack_size / arch.PAGE_SIZE);
    if (stack_phys == 0)
        @panic("cannot allocate stack\n");
    for (0..40) |idx| {
        krn.mm.virt_memory_manager.mapPage(0xC0000000 - ((40 - idx) * arch.PAGE_SIZE), stack_phys + (idx * arch.PAGE_SIZE), .{ .user = true });
    }
    const stack_ptr: [*]u8 = @ptrFromInt(0xC0000000 - (40 * arch.PAGE_SIZE));
    @memset(stack_ptr[0..stack_size], 0);

    krn.logger.INFO("Userspace code:  0x{X:0>8} 0x{X:0>8}", .{userspace_offset, userspace.len});
    krn.logger.INFO("Userspace stack: 0x{X:0>8} 0x{X:0>8}", .{0xC0000000 - 40 * arch.PAGE_SIZE, 0xC0000000});
    krn.logger.INFO("Userspace EIP (_start): 0x{X:0>8}", .{ehdr.e_entry});

    arch.gdt.tss.esp0 = krn.task.current.regs.esp;
    heap_start = arch.pageAlign(heap_start, false);
    krn.logger.INFO("heap_start {x}\n", .{heap_start});
    krn.mm.proc_mm.init_mm.heap = heap_start;

    asm volatile(
        \\ cli
        \\ mov $((8 * 4) | 3), %%bx
        \\ mov %%bx, %%ds
        \\ mov %%bx, %%es
        \\ mov %%bx, %%fs
        \\ mov %%bx, %%gs
        \\
        \\ push $((8 * 4) | 3)
        \\ push %[us]
        \\ pushf
        \\ pop %%ebx
        \\ or $0x200, %%ebx
        \\ push %%ebx
        \\ push $((8 * 3) | 3)
        \\ push %[uc]
        \\ iret
        \\
        ::
        // [uc] "r" (ehdr.e_entry),  // Should be like this, but libc initialization is not working now
        [uc] "r" (userspace_offset),           // main is always at 0x1000 from start
        [us] "r" (0xC0000000),
    );
}
