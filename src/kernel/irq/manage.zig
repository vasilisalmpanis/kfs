const arch = @import("arch");


/// fn () void;
pub const ISRHandler = anyopaque;

/// fn (regs: *Regs) void;
pub const ExceptionHandler = anyopaque;

pub var handlers: [arch.IDT_MAX_DESCRIPTORS] ?* const ISRHandler = .{null} ** arch.IDT_MAX_DESCRIPTORS;
pub var args: [arch.IDT_MAX_DESCRIPTORS] ?*anyopaque = .{null} ** arch.IDT_MAX_DESCRIPTORS;

pub fn mapAll() void {
    if (arch.smp.ioapic.controller) |*cntr| {
        for (1..arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT) |irq_num| {
            if (handlers[irq_num + arch.CPU_EXCEPTION_COUNT] != null)
                cntr.setIRQ(
                    irq_num,
                    @intCast(arch.CPU_EXCEPTION_COUNT + irq_num)
                ) catch {};
        }
    }
}

pub fn registerHandler(irq_num: u32, hndl: *const ISRHandler, arg: ?*anyopaque) callconv(.c) void {
    if (irq_num >= arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXCEPTION_COUNT] = hndl;
    args[irq_num + arch.CPU_EXCEPTION_COUNT] = arg;
    if (irq_num > 0 and irq_num < 16) {
        if (arch.smp.ioapic.controller) |*cntr|
            cntr.setIRQ(
                irq_num,
                @intCast(arch.CPU_EXCEPTION_COUNT + irq_num)
            ) catch {};
    }
}

pub fn unregisterHandler(irq_num: u32) callconv(.c) void {
    if (irq_num >= arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXCEPTION_COUNT] = null;
    args[irq_num + arch.CPU_EXCEPTION_COUNT] = null;
    if (irq_num > 0 and irq_num < 16) {
        if (arch.smp.ioapic.controller) |*cntr|
            cntr.maskIrq(
                irq_num,
                @intCast(arch.CPU_EXCEPTION_COUNT + irq_num)
            ) catch {};
    }
}

pub fn registerIPIHandler(raw_irq_num: u32) callconv(.c) void {
    if (raw_irq_num < arch.MAX_SYSTEM_INTERRUPTS)
        @panic("Wrong IRQ number provided");

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
