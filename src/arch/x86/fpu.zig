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
pub fn isFPUPresent() bool {
    // Read CR0
    const cr0 = asm volatile (
        \\ mov %%cr0, %[result]
        : [result] "={eax}" (-> u32),
    );

    // Check if EM (Emulate) bit is clear (0 = FPU present)
    return (cr0 & (1 << 2)) == 0;
}

/// Check if FPU is available for use (TS bit in CR0)
/// Returns true if FPU is available
pub fn isFPUAvailable() bool {
    const cr0 = asm volatile (
        \\ mov %%cr0, %[result]
        : [result] "={eax}" (-> u32),
    );

    // Check TS (Task Switched) bit - if set, FPU context needs to be loaded
    return (cr0 & (1 << 3)) == 0;
}

/// Set TS (Task Switched) bit in CR0 to indicate FPU context switch needed
pub fn setTaskSwitched() void {
    asm volatile (
        \\ mov %%cr0, %%eax
        \\ or $0x8, %%eax
        \\ mov %%eax, %%cr0
        ::: .{ .eax = true, .memory = true });
}

/// Clear TS (Task Switched) bit in CR0
pub fn clearTaskSwitched() void {
    asm volatile (
        \\ mov %%cr0, %%eax
        \\ and $0xFFFFFFF7, %%eax
        \\ mov %%eax, %%cr0
        ::: .{ .eax = true, .memory = true });
}

pub fn initFPU() void {
    if (!isFPUPresent()) {
        krn.logger.ERROR("FPU not present on this CPU\n", .{});
        return;
    }

    krn.logger.INFO("Initializing i486 FPU\n", .{});

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

    krn.logger.INFO("FPU initialized successfully\n", .{});
}

/// Save FPU state to memory
pub fn saveFPUState(state: *FPUState) void {
    asm volatile (
        \\ fnsave (%[ptr])
        :
        : [ptr] "r" (state),
        : .{ .memory = true });
}

/// Restore FPU state from memory
pub fn restoreFPUState(state: *const FPUState) void {
    asm volatile (
        \\ frstor (%[ptr])
        :
        : [ptr] "r" (state),
        : .{ .memory = true });
}

/// Handle Device Not Available exception (FPU context switch)
pub fn handleDeviceNotAvailable() void {
    // Import kernel here to avoid circular imports

    // Check if this is due to FPU being used
    if (!isFPUAvailable()) {
        const current_task = krn.task.current;

        // If this task hasn't used FPU before, initialize it
        if (!current_task.fpu_used) {
            clearTaskSwitched();
            initFPU();
            current_task.fpu_used = true;
        } else {
            // Restore the task's FPU context
            clearTaskSwitched();
            restoreFPUState(&current_task.fpu_state);
        }
    }
}

/// Save FPU context for task switching
pub fn saveTaskFPUContext(task: anytype) void {
    if (task.fpu_used) {
        saveFPUState(&task.fpu_state);
    }
}

/// Restore FPU context for task switching
pub fn restoreTaskFPUContext(task: anytype) void {
    if (task.fpu_used) {
        restoreFPUState(&task.fpu_state);
        clearTaskSwitched();
    } else {
        // Task hasn't used FPU yet, set TS bit to cause #NM on first use
        setTaskSwitched();
    }
}
