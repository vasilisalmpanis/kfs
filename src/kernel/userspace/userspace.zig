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
    const stack_pages: u32 = 40;
    const userspace_offset: u32 = 0x1000;
    var heap_start: u32 = 0;

    // krn.mm.virt_memory_manager.mapPage(
    //     0,
    //     krn.mm.virt_memory_manager.pmm.allocPage(),
    //     .{.user = true}
    // );
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(userspace));
    for (0..ehdr.e_phnum) |i| {
        const p_hdr: *std.elf.Elf32_Phdr = @ptrCast(
            @constCast(@alignCast(&userspace[ehdr.e_phoff + (ehdr.e_phentsize * i)]))
        );
        const header_type: PT_TYPE = @enumFromInt(p_hdr.p_type);
        if (header_type != PT_TYPE.PT_LOAD) {
            continue;
        }
        var num_pages = p_hdr.p_memsz / arch.PAGE_SIZE;
        if (!arch.isPageAligned(p_hdr.p_memsz))
            num_pages += 1;
        const phys = krn.mm.virt_memory_manager.pmm.allocPages(num_pages);
        if (phys == 0)
            @panic("Cannot go to userspace");
        for (0..num_pages) |idx| {
            krn.mm.virt_memory_manager.mapPage(
                p_hdr.p_vaddr + (idx * arch.PAGE_SIZE),
                phys + (idx * arch.PAGE_SIZE),
                .{ .user = true, }
            );
        }
        const section_ptr: [*]u8 = @ptrFromInt(p_hdr.p_vaddr);
        if (p_hdr.p_filesz > 0) {
            @memcpy(
                section_ptr[0..p_hdr.p_filesz],
                userspace[p_hdr.p_offset..p_hdr.p_offset + p_hdr.p_filesz]
            );
        }
        if (p_hdr.p_memsz > p_hdr.p_filesz) {
            @memset(section_ptr[p_hdr.p_filesz..p_hdr.p_memsz], 0);
        }
        if (p_hdr.p_vaddr + p_hdr.p_memsz > heap_start)
            heap_start = p_hdr.p_vaddr + p_hdr.p_memsz;
    }
    const stack_size: u32 = stack_pages * arch.PAGE_SIZE;
    const stack_phys: u32 = krn.mm.virt_memory_manager.pmm.allocPages(stack_size / arch.PAGE_SIZE);
    if (stack_phys == 0)
        @panic("cannot allocate stack\n");
    const stack_bottom: u32 = krn.mm.PAGE_OFFSET - stack_pages * arch.PAGE_SIZE;
    for (0..stack_pages) |idx| {
        krn.mm.virt_memory_manager.mapPage(
            stack_bottom + idx * arch.PAGE_SIZE,
            stack_phys + (idx * arch.PAGE_SIZE),
            .{ .user = true }
        );
    }
    const stack_ptr: [*]u8 = @ptrFromInt(stack_bottom);
    @memset(stack_ptr[0..stack_size], 0);

    krn.logger.INFO("Userspace code:  0x{X:0>8}", .{userspace_offset});
    krn.logger.INFO("Userspace stack: 0x{X:0>8} 0x{X:0>8}", .{stack_bottom, stack_bottom + stack_size});
    krn.logger.INFO("Userspace EIP (_start): 0x{X:0>8}", .{ehdr.e_entry});

    arch.gdt.tss.esp0 = krn.task.current.regs.esp;
    heap_start = arch.pageAlign(heap_start, false);
    krn.logger.INFO("heap_start 0x{X:0>8}\n", .{heap_start});
    krn.mm.proc_mm.init_mm.heap = heap_start;
    krn.mm.proc_mm.init_mm.stack_bottom = stack_bottom;
    krn.mm.proc_mm.init_mm.stack_top = stack_bottom + stack_size - arch.PAGE_SIZE;

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
        [us] "r" (stack_bottom + stack_size - arch.PAGE_SIZE),
    );
}
