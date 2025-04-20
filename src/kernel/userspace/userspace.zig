const std = @import("std");
const arch = @import("arch");
const krn = @import("../main.zig");

pub fn goUserspace(userspace: []const u8) void {
    const userspace_offset: u32 = 0x1000;

    const page_count: u32 = (userspace.len - userspace_offset) / krn.mm.PAGE_SIZE + 1;
    var virt_addr = userspace_offset;
    for (0..page_count) |_| {
        const phys = krn.mm.virt_memory_manager.pmm.allocPage();
        krn.mm.virt_memory_manager.mapPage(
            virt_addr,
            phys,
            .{.user = true}
        );
        virt_addr += krn.mm.PAGE_SIZE;
    }

    const code_ptr: [*]u8 = @ptrFromInt(userspace_offset);
    @memcpy(code_ptr[0..], userspace[userspace_offset..]);

    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(userspace));
    // const programm_header: *std.elf.Elf32_Phdr = @ptrFromInt(code + ehdr.e_phoff);

    const stack_size: u32 = 4096;
    const stack = krn.mm.uheap.alloc(
        stack_size,
        true, true
    ) catch 0;
    const stack_ptr: [*]u8 = @ptrFromInt(stack);
    @memset(stack_ptr[0..stack_size], 0);

    krn.logger.INFO("Userspace code:  0x{X:0>8} 0x{X:0>8}", .{userspace_offset, userspace.len});
    krn.logger.INFO("Userspace stack: 0x{X:0>8} 0x{X:0>8}", .{stack, stack + stack_size});
    krn.logger.INFO("Userspace EIP (_start): 0x{X:0>8}", .{ehdr.e_entry});

    arch.gdt.tss.esp0 = krn.task.current.regs.esp;

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
        [us] "r" (stack + stack_size),
    );
}
