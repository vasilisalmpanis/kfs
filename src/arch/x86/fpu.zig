const krn = @import("kernel");
const io = @import("io.zig");

/// FPU state structure - 108 bytes for i486 FPU
pub const FPUState = extern struct {
    control: u16,
    _reserved1: u16,
    status: u16,
    _reserved2: u16,
    tag: u16,
    _reserved3: u16,
    fip: u32,
    fcs: u16,
    _reserved4: u16,
    fdp: u32,
    fds: u16,
    _reserved5: u16,
    st: [8][10]u8,
};

/// Check if FPU is present by testing CR0.EM bit
/// Returns true if FPU is present
pub inline fn isFPUPresent() bool {
    // Read CR0
    const cr0 = asm volatile (
        \\ mov %%cr0, %[result]
        : [result] "={eax}" (-> u32),
    );

    // Check if EM (Emulate) bit is clear (0 = FPU present)
    return (cr0 & (1 << 2)) == 0;
}

/// Set TS (Task Switched) bit in CR0 to indicate FPU context switch needed
pub inline fn setTaskSwitched() void {
    asm volatile (
        \\ mov %%cr0, %%eax
        \\ or $0x8, %%eax
        \\ mov %%eax, %%cr0
        ::: .{ .eax = true, .memory = true });
}

/// Clear TS (Task Switched) bit in CR0
pub inline fn clearTaskSwitched() void {
    asm volatile (
        \\ clts
    );
}

pub fn initFPU() void {
    if (!isFPUPresent()) {
        return;
    }

    asm volatile ("fninit");

    // Set FPU control word for proper operation
    // Default control word: 0x037F
    // - Precision: 64-bit mantissa
    // - Rounding: Round to nearest
    // - Exception masks: All exceptions masked
    asm volatile (
        \\ fldcw %[control]
        :
        : [control] "m" (@as(u16, 0x037F)),
    );

    // Clear any pending exceptions
    asm volatile ("fnclex");

    setTaskSwitched();
    krn.serial.print("FPU initialized successfully\n");
}

pub inline fn initFPUState() void {
    asm volatile (
        \\ fninit
    );
}

/// Save FPU state to memory
pub inline fn saveFPUState(state: *FPUState) void {
    asm volatile (
        \\ fnsave (%[ptr])
        :
        : [ptr] "r" (state),
        : .{ .memory = true });
}

/// Restore FPU state from memory
pub inline fn restoreFPUState(state: *const FPUState) void {
    asm volatile (
        \\ frstor (%[ptr])
        :
        : [ptr] "r" (state),
        : .{ .memory = true });
}

/// Handle Device Not Available exception (FPU context switch)
pub fn handleDeviceNotAvailable() void {
    clearTaskSwitched();
    asm volatile ("fnclex");
    const current_task = krn.task.current;

    if (current_task.fpu_used) {
        restoreFPUState(&current_task.fpu_state);
    } else {
        // If this task hasn't used FPU before, initialize it
        initFPUState();
        current_task.fpu_used = true;
    }
    current_task.save_fpu_state = true;
}
