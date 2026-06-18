const tsk = @import("kernel").task;
const krn = @import("kernel");
const gdt = @import("../gdt.zig");
const vmm = @import("../mm/vmm.zig");
const fpu = @import("../fpu.zig");

extern const stack_top: u32;

// switch_to(prev_save: *u32, next_sp: u32)
//
// prev_save: pointer to the per_task kernel_esp
// next_sp: The stack pointer to change to
//
// Pushes prev's callee-saved registers, stores the resulting esp into
// *prev_save (parking prev), loads next_sp into esp (the synchronous stack
// switch), restores next's callee-saved registers and `ret`s into wherever
// next last parked. cdecl: after the four pushes, ret addr is at 16(%esp),
// prev_save at 20(%esp), next_sp at 24(%esp).
//
// Stack layout:
// [esp + 0]  = edi          ← just pushed
// [esp + 4]  = esi
// [esp + 8]  = ebx
// [esp + 12] = ebp
// [esp + 16] = return address
// [esp + 20] = prev_save  (arg0)
// [esp + 24] = next_sp    (arg1)
comptime {
    asm (
        \\.global switch_to
        \\.type switch_to, @function
        \\switch_to:
        \\  push %ebp
        \\  push %ebx
        \\  push %esi
        \\  push %edi
        \\  movl 20(%esp), %eax
        \\  movl %esp, (%eax)
        \\  movl 24(%esp), %esp
        \\  pop %edi
        \\  pop %esi
        \\  pop %ebx
        \\  pop %ebp
        \\  ret
    );
}

extern fn switch_to(prev_save: *u32, next_sp: u32) callconv(.c) void;

// Bottom part of Generate IRQ stub to return from freshly forked
// process
pub fn retFromFork() callconv(.naked) noreturn {
    asm volatile (
        \\ pop %gs
        \\ pop %fs
        \\ pop %es
        \\ pop %ds
        \\ popa
        \\ add $12, %esp
        \\ iret
    );
}

/// Builds the initial switch frame on a new task's kernel stack so the first
/// switch_to lands on `trampoline`.
///
/// Layout written, from low to high address:
///   [kesp+0]  edi = 0
///   [kesp+4]  esi = 0
///   [kesp+8]  ebx = 0
///   [kesp+12] ebp = 0
///   [kesp+16] return address = trampoline
/// Returns kesp, which the caller stores in task.kernel_esp.
pub fn setupSwitchFrame(esp_after_ret: usize, trampoline: usize) u32 {
    const kesp: usize = esp_after_ret - 5 * @sizeOf(u32);
    const frame: [*]u32 = @ptrFromInt(kesp);
    frame[0] = 0; // edi
    frame[1] = 0; // esi
    frame[2] = 0; // ebx
    frame[3] = 0; // ebp
    frame[4] = @intCast(trampoline); // ret addr
    return @intCast(kesp);
}

/// Must be called with interrupts disabled.
pub fn contextSwitch(prev: *tsk.Task, next: *tsk.Task) void {
    @setRuntimeSafety(false);
    if (prev.save_fpu_state) {
        if (prev.fpu_state) |fpu_state| {
            fpu.saveFPUState(fpu_state);
            fpu.setTaskSwitched();
        }
        prev.save_fpu_state = false;
    }
    tsk.current = next;
    if (next == &tsk.initial_task) {
        gdt.tss.esp0 = @intFromPtr(&stack_top);
    } else {
        gdt.tss.esp0 = next.stack_bottom + krn.STACK_SIZE;
    }
    vmm.switchToVAS(next.mm.?.vas);

    var access: u8 = 0;
    access |= 0x10; // S=1
    access |= 0x60; // DPL=3
    access |= 0x02; // data, writable
    access |= 0x80; // P=1  (force present, don't trust user)

    var gran: u8 = 0;
    gran |= 0x80; // G=1 (pages)
    gran |= 0x40; // D=1 (32-bit)
    gran |= 0x10; // AVL=1 (harmless)
    gdt.gdtSetEntry(
        gdt.GDT_TLS0_INDEX,
        next.tls,
        next.limit,
        access,
        gran,
    );
    const sel: u16 = @intCast((gdt.GDT_TLS0_INDEX << 3) | 0x3);
    asm volatile (
        "mov %[_sel], %gs"
        :: [_sel]"r"(sel)
        : .{ .memory = true}
    );

    switch_to(&prev.kernel_esp, next.kernel_esp);
}
