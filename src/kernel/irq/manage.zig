const arch = @import("arch");
const MAX_IRQ = 256;

pub const ISRHandler = fn () void;

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
