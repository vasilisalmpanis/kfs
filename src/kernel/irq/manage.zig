const arch = @import("arch");


/// fn () void;
pub const ISRHandler = anyopaque;

/// fn (regs: *Regs) void;
pub const ExceptionHandler = anyopaque;

pub var handlers: [arch.IDT_MAX_DESCRIPTORS] ?* const ISRHandler = .{null} ** arch.IDT_MAX_DESCRIPTORS;

pub fn registerHandler(irq_num: u32, hndl: *const ISRHandler) void {
    if (irq_num >= arch.IDT_MAX_DESCRIPTORS - arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXCEPTION_COUNT] = hndl;
}

pub fn unregisterHandler(irq_num: u32) void {
    if (irq_num >= arch.IDT_MAX_DESCRIPTORS - arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXCEPTION_COUNT] = null;
}

pub fn registerExceptionHandler(int_num: u32, hndl: *const ExceptionHandler) void {
    if (int_num >= arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong exception number");
    handlers[int_num] = hndl;
}

pub fn unregisterExceptionHandler(int_num: u32) void {
    if (int_num >= arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong exception number");
    handlers[int_num] = null;
}
