const arch = @import("arch");
const MAX_IRQ = 256;

/// fn () void;
pub const ISRHandler = anyopaque;

/// fn (regs: *registers_t) void;
pub const ExceptionHandler = anyopaque;


pub var handlers: [256] ?* const ISRHandler = .{null} ** 256;

pub fn register_handler(irq_num: u32, hndl: *const ISRHandler) void {
    if (irq_num >= MAX_IRQ - 32)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + 32] = hndl;
}

pub fn unregister_handler(irq_num: u32) void {
    if (irq_num >= MAX_IRQ - 32)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + 32] = null;
}

pub fn register_exception_handler(int_num: u32, hndl: *const ExceptionHandler) void {
    if (int_num > 31)
        @panic("Wrong exception number");
    handlers[int_num] = hndl;
}

pub fn unregister_exception_handler(int_num: u32) void {
    if (int_num > 31)
        @panic("Wrong exception number");
    handlers[int_num] = null;
}
