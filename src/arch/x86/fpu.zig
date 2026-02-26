const krn = @import("kernel");
const cpuid = @import("system/cpuid.zig");

const CR0_MP: u32 = 1 << 1;
const CR0_EM: u32 = 1 << 2;
const CR0_TS: u32 = 1 << 3;
const CR0_NE: u32 = 1 << 5;

const CR4_OSFXSR:       u32 = 1 << 9;
const CR4_OSXMMEXCPT:   u32 = 1 << 10;

const MXCSR_DEFAULT:    u32 = 0x1F80;

const Backend = enum {
    NONE,
    MMX,
    SSE,
};

pub const FPUState = extern struct {
    raw: [512 + 15]u8 = .{0} ** (512 + 15),

    pub inline fn ptrAligned(self: *FPUState) *align(16) [512]u8 {
        const aligned = (@intFromPtr(&self.raw) + 15) & ~@as(usize, 15);
        return @ptrFromInt(aligned);
    }

    pub inline fn constPtrAligned(self: *const FPUState) *const align(16) [512]u8 {
        const aligned = (@intFromPtr(&self.raw) + 15) & ~@as(usize, 15);
        return @ptrFromInt(aligned);
    }
};

var backend: Backend = .NONE;

pub inline fn supportsTaskState() bool {
    return backend != .NONE;
}

/// Check if FPU is present by testing CR0.EM bit
/// Returns true if FPU is present
pub inline fn isFPUPresent() bool {
    // Read CR0
    const cr0 = asm volatile (
        \\ mov %%cr0, %[result]
        : [result] "={eax}" (-> u32),
    );

    // Check if EM (Emulate) bit is clear (0 = FPU present)
    return (cr0 & CR0_EM) == 0;
}

/// Set TS (Task Switched) bit in CR0 to indicate FPU context switch needed
pub inline fn setTaskSwitched() void {
    if (!supportsTaskState())
        return;
    asm volatile (
        \\ mov %%cr0, %%eax
        \\ or %[ts], %%eax
        \\ mov %%eax, %%cr0
        :
        : [ts] "i" (CR0_TS),
        : .{ .eax = true, .memory = true }
    );
}

/// Clear TS (Task Switched) bit in CR0
pub inline fn clearTaskSwitched() void {
    asm volatile (
        \\ clts
    );
}

fn loadDefaultMxcsr() void {
    var mxcsr: u32 = MXCSR_DEFAULT;
    asm volatile (
        \\ ldmxcsr (%[ptr])
        :
        : [ptr] "r" (&mxcsr),
        : .{ .memory = true }
    );
}

fn selectBackend() Backend {
    if (!cpuid.info.supported)
        return .NONE;
    if (
        cpuid.info.features.edx.fpu
        and cpuid.info.features.edx.mmx
        and cpuid.info.features.edx.fxsr
        and cpuid.info.features.edx.sse
    )
        return .SSE;
    if (
        cpuid.info.features.edx.fpu
        and cpuid.info.features.edx.mmx
    )
        return .MMX;
    return .NONE;
}

pub fn initFPU() void {
    if (!isFPUPresent()) {
        backend = .NONE;
        krn.logger.WARN("fpu: no x87 present", .{});
        return;
    }

    backend = selectBackend();
    krn.logger.WARN("fpu backend: {t}", .{backend});

    if (backend == .NONE) {
        krn.logger.WARN("fpu: disabling hardware fp", .{});
        asm volatile (
            \\ mov %%cr0, %%eax
            \\ or %[em], %%eax
            \\ and %[clear_ts], %%eax
            \\ mov %%eax, %%cr0
            :
            : [em] "i" (CR0_EM),
              [clear_ts] "i" (~CR0_TS),
            : .{ .eax = true, .memory = true }
        );
        return;
    }

    asm volatile (
        \\ mov %%cr0, %%eax
        \\ and %[clear_em], %%eax
        \\ or %[set_bits], %%eax
        \\ mov %%eax, %%cr0
        :
        : [clear_em] "i" (~CR0_EM),
          [set_bits] "i" (CR0_MP | CR0_NE),
        : .{ .eax = true, .memory = true }
    );

    clearTaskSwitched();

    if (backend == .SSE) {
        asm volatile (
            \\ mov %%cr4, %%eax
            \\ or %[set_bits], %%eax
            \\ mov %%eax, %%cr4
            :
            : [set_bits] "i" (CR4_OSFXSR | CR4_OSXMMEXCPT),
            : .{ .eax = true, .memory = true }
        );
    }

    asm volatile ("fninit");
    if (backend == .SSE)
        loadDefaultMxcsr();

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
    if (backend == .SSE)
        loadDefaultMxcsr();
}

/// Save FPU state to memory
pub inline fn saveFPUState(state: *FPUState) void {
    if (backend == .SSE) {
        asm volatile (
            \\ fxsave (%[ptr])
            :
            : [ptr] "r" (state.ptrAligned()),
            : .{ .memory = true }
        );
    } else if (backend == .MMX) {
        asm volatile (
            \\ fnsave (%[ptr])
            :
            : [ptr] "r" (state.ptrAligned()),
            : .{ .memory = true }
        );
    }
}

/// Restore FPU state from memory
pub inline fn restoreFPUState(state: *const FPUState) void {
    if (backend == .SSE) {
        asm volatile (
            \\ fxrstor (%[ptr])
            :
            : [ptr] "r" (state.constPtrAligned()),
            : .{ .memory = true }
        );
    } else if (backend == .MMX) {
        asm volatile (
            \\ frstor (%[ptr])
            :
            : [ptr] "r" (state.constPtrAligned()),
            : .{ .memory = true }
        );
    }
}

/// Handle Device Not Available exception (FPU context switch)
pub fn handleDeviceNotAvailable() void {
    if (!supportsTaskState())
        return;
    clearTaskSwitched();
    asm volatile ("fnclex");
    const current_task = krn.task.current;

    if (current_task.fpu_state) |state| {
        if (current_task.fpu_used) {
            restoreFPUState(state);
        } else {
            // If this task hasn't used FPU before, initialize it
            initFPUState();
            current_task.fpu_used = true;
        }
    } else {
        const state = krn.mm.kmalloc(FPUState)
            orelse @panic("Cannot allocate FPU state");
        current_task.fpu_state = state;
        initFPUState();
        current_task.fpu_used = true;
    }
    current_task.save_fpu_state = true;
}
