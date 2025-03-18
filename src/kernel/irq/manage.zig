const arch = @import("arch");


/// fn () void;
pub const ISRHandler = anyopaque;

/// fn (regs: *registers_t) void;
pub const ExceptionHandler = anyopaque;

pub var handlers: [arch.IDT_MAX_DESCRIPTORS] ?* const ISRHandler = .{null} ** arch.IDT_MAX_DESCRIPTORS;

pub fn register_handler(irq_num: u32, hndl: *const ISRHandler) void {
    if (irq_num >= arch.IDT_MAX_DESCRIPTORS - arch.CPU_EXPECTIONS_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXPECTIONS_COUNT] = hndl;
}

pub fn unregister_handler(irq_num: u32) void {
    if (irq_num >= arch.IDT_MAX_DESCRIPTORS - arch.CPU_EXPECTIONS_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXPECTIONS_COUNT] = null;
}

pub fn register_exception_handler(int_num: u32, hndl: *const ExceptionHandler) void {
    if (int_num >= arch.CPU_EXPECTIONS_COUNT)
        @panic("Wrong exception number");
    handlers[int_num] = hndl;
}

pub fn unregister_exception_handler(int_num: u32) void {
    if (int_num >= arch.CPU_EXPECTIONS_COUNT)
        @panic("Wrong exception number");
    handlers[int_num] = null;
}
