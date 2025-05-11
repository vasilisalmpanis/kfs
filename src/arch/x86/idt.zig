const io = @import("io.zig");
const std = @import("std");
const dbg = @import("debug");
const drv = @import("drivers");
const krn = @import("kernel");
const printf = @import("debug").printf;
const Regs = @import("system/cpu.zig").Regs;
const signals = @import("kernel").signals;
const tsk = @import("kernel").task;

pub const IDT_MAX_DESCRIPTORS   = 256;
pub const CPU_EXCEPTION_COUNT   = 32;

pub const SYSCALL_INTERRUPT = 0x80;
pub const TIMER_INTERRUPT   = 0x20;

pub const KERNEL_CODE_SEGMENT   = 0x08;
pub const KERNEL_DATA_SEGMENT   = 0x10;
pub const USER_CODE_SEGMENT   = 0x18;
pub const USER_DATA_SEGMENT   = 0x20;

const ExceptionHandler  = fn (regs: *Regs) void;
const SyscallHandler    = fn (regs: *Regs) void;
const ISRHandler        = fn () callconv(.C) void;

pub export fn exceptionHandler(state: *Regs) callconv(.C) void {
    krn.logger.DEBUG("EXC {d}", .{state.int_no});
    if (krn.irq.handlers[state.int_no] != null) {
        const handler: *const ExceptionHandler = @ptrCast(krn.irq.handlers[state.int_no].?);
        handler(state);
    }
}

pub export fn irqHandler(state: *Regs) callconv(.C) *Regs {
    var new_state: *Regs = state;
    if (krn.irq.handlers[state.int_no] != null) {
        if (state.int_no == SYSCALL_INTERRUPT) {
            const handler: *const SyscallHandler = @ptrCast(krn.irq.handlers[state.int_no].?);
            handler(state);
        } else {
            const handler: *const ISRHandler = @ptrCast(krn.irq.handlers[state.int_no].?);
            handler();
        }
    }
    io.outb(0x20, 0x20);
    if (state.int_no >= 40) {
        io.outb(0xA0, 0x20);
    }
    if (state.int_no == TIMER_INTERRUPT) {
        new_state = krn.sched.schedule(state);
    }
    if (tsk.current.tsktype != .KTHREAD)
        new_state = signals.processSignals(new_state);
    return new_state;
}

const ErrorCodes = std.EnumMap(krn.exceptions.Exceptions, bool).init(.{
    .DivisionError = false,
    .Debug = false,
    .NonMaskableInterrupt = false,
    .Breakpoint = false,
    .Overflow = false,
    .BoundRangeExceeded = false,
    .InvalidOpcode = false,
    .DeviceNotAvailable = false,
    .DoubleFault = true,
    .CoprocessorSegmentOverrun = false,
    .InvalidTSS = true,
    .SegmentNotPresent = true,
    .StackSegmentFault = true,
    .GeneralProtectionFault = true,
    .PageFault = true,
    .Reserved_1 = false,
    .x87FloatingPointException = false,
    .AlignmentCheck = true,
    .MachineCheck = false,
    .SIMDFloatingPointException = false,
    .VirtualizationException = false,
    .ControlProtectionException = true,
    .Reserved_2 = false,
    .Reserved_3 = false,
    .Reserved_4 = false,
    .Reserved_5 = false,
    .Reserved_6 = false,
    .Reserved_7 = false,
    .HypervisorInjectionException = false,
    .VMMCommunicationException = true,
    .SecurityException = true,
    .Reserved_8 = false,
});

pub const push_regs: []const u8 =
\\    pusha
\\    push %ds
\\    push %es
\\    push %fs
\\    push %gs
\\    mov $0x10, %ax
\\    mov %ax, %ds
\\    mov %ax, %es
\\    mov %ax, %fs
\\    mov %ax, %gs
\\
;

pub const pop_regs: []const u8 =
\\
\\    pop %gs
\\    pop %fs
\\    pop %es
\\    pop %ds
\\    popa
\\
;

pub fn generateIRQStub(comptime n: u8) []const u8 {
    return std.fmt.comptimePrint(
        \\irq_stub_{d}:
        \\ cli
        \\ push $0
        \\ push ${d}
        \\ {s}
        \\ mov %esp, %eax
        \\ push %eax
        \\ lea irqHandler, %eax
        \\ call *%eax
        \\ add $4, %esp
        \\ mov %eax, %esp
        \\ {s}
        \\ add $8, %esp
        \\ iret
        \\
        , .{n, n, push_regs, pop_regs}
    );
}

// Generate assembly for a single ISR stub
fn generateStub(comptime n: u8, comptime has_error: bool) []const u8 {
    return std.fmt.comptimePrint(
        \\isr_stub_{d}:
        \\ cli
        \\ {s}
        \\ push ${d}
        \\ {s}
        \\ mov %esp, %eax
        \\ push %eax
        \\ lea exceptionHandler, %eax
        \\ call *%eax
        \\ add $4, %esp
        \\ mov %eax, %esp
        \\ {s}
        \\ add $8, %esp
        \\ iret
        \\
        , .{n, if (has_error) "" else "push $0", n, push_regs, pop_regs}
    );
}

// // Generate all ISR stubs at compile time
comptime {
    // Generate assembly for all stubs
    var asm_source: []const u8 = "";
    for (0..CPU_EXCEPTION_COUNT) |i| {
        const except: krn.exceptions.Exceptions = @enumFromInt(i);
        asm_source = asm_source ++ generateStub(
            @intCast(i),
            ErrorCodes.get(except) orelse false
        );
    }
    for (CPU_EXCEPTION_COUNT..IDT_MAX_DESCRIPTORS) |i| {
        asm_source = asm_source ++ generateIRQStub(@intCast(i));
    }
    // Emit the assembly
    asm(asm_source);
}

// Create the ISR stub table
pub export var isr_stub_table: [IDT_MAX_DESCRIPTORS]*const ISRHandler align(4) linksection(".data") = init: {
    var table: [IDT_MAX_DESCRIPTORS]*const ISRHandler = undefined;
    for (0..CPU_EXCEPTION_COUNT) |i| {
        table[i] = @extern(
            *const ISRHandler,
            .{
                .name = std.fmt.comptimePrint("isr_stub_{d}", .{i})
            }
        );
    }
    for (CPU_EXCEPTION_COUNT..IDT_MAX_DESCRIPTORS) |i| {
        table[i] = @extern(
            *const ISRHandler,
            .{
                .name = std.fmt.comptimePrint("irq_stub_{d}", .{i})
            }
        );
    }
    break :init table;
};

fn IRQClearMask(IRQ_line: u8) void {
    var IRQline: u8 = IRQ_line;
    var port: u16 = undefined;
    var value: u8 = undefined;

    if(IRQline < 8) {
        port = 0x21;
    } else {
        port = 0xA1;
        IRQline -= 8;
    }
    value = io.inb(port);
    io.outb(port, value & ~(@as(u8, 1) << @truncate(IRQline)));        
}

pub inline fn PICRemap() void {
    io.outb(0x20, 0x11);
    io.outb(0xA0, 0x11);
    io.outb(0x21, 0x20);
    io.outb(0xA1, 0x28);
    io.outb(0x21, 0x04);
    io.outb(0xA1, 0x02);
    io.outb(0x21, 0x01);
    io.outb(0xA1, 0x01);
    io.outb(0x21, 0x0);
    io.outb(0xA1, 0x0);
}

const IdtEntry = packed struct {
    isr_low: u16,       // The lower 16 bits of the ISR's address
    kernel_cs: u16,     // The GDT segment selector that the CPU will load into CS before calling the ISR
    reserved: u8,       // Set to zero
    attributes: u8,     // Type and attributes; see the IDT page
    isr_high: u16,      // The higher 16 bits of the ISR's address
};

const Idtr = packed struct {
    limit: u16,
    base: *const IdtEntry,
};

var idt: [IDT_MAX_DESCRIPTORS] IdtEntry align(0x10) = undefined;
var idtr: Idtr = undefined;

pub fn idtSetDescriptor(vector: u8, isr: *const ISRHandler, flags: u8) void {
    const descriptor: *IdtEntry = &idt[vector];

    descriptor.isr_low        = @as(u16, @truncate(@intFromPtr(isr) & 0xFFFF));
    descriptor.isr_high       = @as(u16, @truncate(@intFromPtr(isr) >> 16));
    descriptor.kernel_cs      = KERNEL_CODE_SEGMENT; // this value can be whatever offset your kernel code selector is in your GDT
    descriptor.attributes     = flags;
    descriptor.reserved       = 0;
}

pub fn idtInit() void {
    idtr.base = &idt[0];
    idtr.limit = idt.len * @sizeOf(IdtEntry) - 1;

    for (0..IDT_MAX_DESCRIPTORS) |index| {
        idt[index] = IdtEntry{
            .attributes =  0,
            .isr_high =  0,
            .isr_low = 0,
            .kernel_cs = 0,
            .reserved = 0,
    };
    }
    for (0..IDT_MAX_DESCRIPTORS) |index| {
        idtSetDescriptor(
            @intCast(index),
            isr_stub_table[index],
            if (index < CPU_EXCEPTION_COUNT) 0x8E else 0xEE
        );
    }
    
    asm volatile (
        \\lidt (%[idt_ptr])
        :
        : [idt_ptr] "r" (&idtr),
    );
    PICRemap();
    krn.exceptions.registerExceptionHandlers();
    asm volatile ("sti"); // set the interrupt flag
}
