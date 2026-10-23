const arch = @import("arch");
const errors = @import("../syscalls/error-codes.zig").PosixError;


/// fn () void;
pub const ISRHandler = anyopaque;

/// fn (regs: *Regs) void;
pub const ExceptionHandler = anyopaque;

pub var handlers: [arch.IDT_MAX_DESCRIPTORS] ?* const ISRHandler = @splat(null);
pub var args: [arch.IDT_MAX_DESCRIPTORS] ?*anyopaque = @splat(null);
var pci_irqs: [arch.IDT_MAX_DESCRIPTORS]bool = @splat(false);

pub fn mapAll() void {
    if (arch.smp.ioapic.controller) |*cntr| {
        for (1..arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT) |irq_num| {
            if (handlers[irq_num + arch.CPU_EXCEPTION_COUNT] != null) {
                if (pci_irqs[irq_num]) {
                    cntr.setPCIIRQ(
                        irq_num,
                        @intCast(arch.CPU_EXCEPTION_COUNT + irq_num),
                        false
                    ) catch {};
                    continue;
                }
                cntr.setIRQ(
                    irq_num,
                    @intCast(arch.CPU_EXCEPTION_COUNT + irq_num)
                ) catch {};
            }
        }
    }
}

pub fn registerHandler(irq_num: u32, hndl: *const ISRHandler, arg: ?*anyopaque) callconv(.c) void {
    if (irq_num >= arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong IRQ number provided");
    handlers[irq_num + arch.CPU_EXCEPTION_COUNT] = hndl;
    args[irq_num + arch.CPU_EXCEPTION_COUNT] = arg;
    pci_irqs[irq_num] = false;
    if (irq_num > 0 and irq_num < 16) {
        if (arch.smp.ioapic.controller) |*cntr|
            cntr.setIRQ(
                irq_num,
                @intCast(arch.CPU_EXCEPTION_COUNT + irq_num)
            ) catch {};
    }
}

pub fn registerPCIHandler(
    irq_num: u32, hndl: *const ISRHandler, arg: ?*anyopaque
) !void {
    if (
        irq_num == 0 or
        irq_num >= arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT
    )
        return errors.EINVAL;
    const vector = irq_num + arch.CPU_EXCEPTION_COUNT;
    if (handlers[vector] != null)
        return errors.EBUSY;
    if (arch.smp.ioapic.controller) |*cntr| {
        try cntr.setPCIIRQ(irq_num, @intCast(vector), true);
        handlers[vector] = hndl;
        args[vector] = arg;
        pci_irqs[irq_num] = true;
        try cntr.setPCIIRQ(irq_num, @intCast(vector), false);
    } else {
        return errors.ENODEV;
    }
}

pub fn unregisterHandler(irq_num: u32) callconv(.c) void {
    if (irq_num >= arch.MAX_SYSTEM_INTERRUPTS - arch.CPU_EXCEPTION_COUNT)
        @panic("Wrong IRQ number provided");
    const is_pci = pci_irqs[irq_num];
    if (is_pci) {
        if (arch.smp.ioapic.controller) |*cntr|
            cntr.setPCIIRQ(
                irq_num,
                @intCast(arch.CPU_EXCEPTION_COUNT + irq_num),
                true
            ) catch {};
        pci_irqs[irq_num] = false;
    }
    handlers[irq_num + arch.CPU_EXCEPTION_COUNT] = null;
    args[irq_num + arch.CPU_EXCEPTION_COUNT] = null;
    if (!is_pci and irq_num > 0 and irq_num < 16) {
        if (arch.smp.ioapic.controller) |*cntr|
            cntr.maskIrq(
                irq_num,
                @intCast(arch.CPU_EXCEPTION_COUNT + irq_num)
            ) catch {};
    }
}

pub fn registerIPIHandler(raw_irq_num: u32, hndl: *const ISRHandler) callconv(.c) void {
    if (raw_irq_num < arch.MAX_SYSTEM_INTERRUPTS or raw_irq_num >= arch.idt.IDT_MAX_DESCRIPTORS)
        @panic("Wrong IRQ number provided");
    handlers[raw_irq_num] = hndl;
}

pub fn unregisterIPIHandler(raw_irq_num: u32) void {
    if (raw_irq_num < arch.MAX_SYSTEM_INTERRUPTS or raw_irq_num >= arch.idt.IDT_MAX_DESCRIPTORS)
        @panic("Wrong IRQ number provided");
    handlers[raw_irq_num] = null;
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
