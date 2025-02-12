const context = @import("./context.zig");
const io = @import("io.zig");
const std = @import("std");
const dbg = @import("debug");
const drv = @import("drivers");
const krn = @import("kernel");
const printf = @import("debug").printf;
const regs = @import("system/cpu.zig").registers_t;
const dump = @import("system/cpu.zig").printRegisters;

const IDT_MAX_DESCRIPTORS = 48;

const idt_entry_t = packed struct {
    isr_low: u16,       // The lower 16 bits of the ISR's address
    kernel_cs: u16,     // The GDT segment selector that the CPU will load into CS before calling the ISR
    reserved: u8,       // Set to zero
    attributes: u8,     // Type and attributes; see the IDT page
    isr_high: u16,      // The higher 16 bits of the ISR's address
};

const idtr_t = packed struct {
    limit: u16,
    base: *const idt_entry_t,
};

var idt: [256] idt_entry_t align(0x10) = undefined;
var idtr: idtr_t = undefined;

pub export fn exception_handler(state: *regs) callconv(.C) void {
    printf("interrupt: {x}\n", .{state.int_no});
    @panic("cpu exception");
}

pub export fn irq_handler(state: *regs) callconv(.C) void {
    if (krn.irq.handlers[state.int_no] != null)
        krn.irq.handlers[state.int_no].?();
    io.outb(0x20, 0x20);
    if (state.int_no >= 40) {
        io.outb(0xA0, 0x20);
    }
    if (state.int_no >= 48)
        krn.logger.INFO("Interrupt {d}\n", .{state.int_no});
}

const ISRHandler = fn () callconv(.C) void;

pub fn idt_set_descriptor(vector: u8, isr: *const ISRHandler, flags: u8) void {
    const descriptor: *idt_entry_t = &idt[vector];

    descriptor.isr_low        = @as(u16, @truncate(@intFromPtr(isr) & 0xFFFF));
    descriptor.isr_high       = @as(u16, @truncate(@intFromPtr(isr) >> 16));
    descriptor.kernel_cs      = 0x08; // this value can be whatever offset your kernel code selector is in your GDT
    descriptor.attributes     = flags;
    descriptor.reserved       = 0;
}

// Define which interrupts have error codes
const error_codes = [_]bool{
    false, false, false, false, false, false, false, false, true,  false,
    true,  true,  true,  true,  true,  false, false, true,  false, false,
    false, false, false, false, false, false, false, false, false, false,
    true,  false
};

fn generateIRQStub(comptime n: u8) []const u8 {
    const stub_name = "irq_stub_" ++ std.fmt.comptimePrint("{d}:\n", .{n});
    return 
        stub_name ++
        \\ cli
        \\ push $0
        \\ push $
        ++ std.fmt.comptimePrint("{d}\n", .{n}) ++
        push_regs ++
        \\ lea irq_handler, %eax
        \\ call *%eax
        ++ pop_regs ++
        \\ add $8, %esp  // Clean up interrupt number
        \\ iret
        \\
    ;
}
const push_regs: []const u8 =
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
\\    mov %esp, %eax
\\    push %eax
\\
;
const pop_regs: []const u8 =
\\
\\    pop %eax
\\    pop %gs
\\    pop %fs
\\    pop %es
\\    pop %ds
\\    popa
\\
;

// Generate assembly for a single ISR stub
fn generateStub(comptime n: u8, comptime has_error: bool) []const u8 {
    const stub_name = "isr_stub_" ++ std.fmt.comptimePrint("{d}:\n", .{n});
    if (has_error) {
        return 
            stub_name ++
            \\ cli
            \\ push $
            ++ std.fmt.comptimePrint("{d}\n", .{n}) ++
            push_regs ++
            \\ lea exception_handler, %eax
            \\ call *%eax
            ++ pop_regs ++
            \\ add $8, %esp
            \\ iret
            \\
        ;
    } else {
        return 
            stub_name ++
            \\ cli
            \\ push $0
            \\ push $
            ++ std.fmt.comptimePrint("{d}\n", .{n}) ++
            push_regs ++
            \\ lea exception_handler, %eax
            \\ call *%eax
            ++ pop_regs ++
            \\ add $8, %esp
            \\ iret
            \\
        ;
    }
}

// // Generate all ISR stubs at compile time
comptime {
    // Generate assembly for all stubs
    var asm_source: []const u8 = "";
    for (0..32) |i| {
        asm_source = asm_source ++ generateStub(@intCast(i), error_codes[i]);
    }
    for (32..48) |i| {
        asm_source = asm_source ++ generateIRQStub(@intCast(i));
    }
    // Emit the assembly
    asm(asm_source);
}

// Create the ISR stub table
pub export var isr_stub_table: [48]*const ISRHandler align(4) linksection(".data") = init: {
    var table: [48]*const ISRHandler = undefined;
    for (0..32) |i| {
        table[i] = @extern(
            *const ISRHandler,
            .{
                .name = "isr_stub_" ++ std.fmt.comptimePrint("{d}", .{i})
            }
        );
    }
    for (32..48) |i| {
        table[i] = @extern(
            *const ISRHandler,
            .{
                .name = "irq_stub_" ++ std.fmt.comptimePrint("{d}", .{i})
            }
        );
    }
    break :init table;
};

fn IRQ_clear_mask(IRQ_line: u8) void {
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

pub inline fn PIC_remap() void {
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

pub fn idt_init() void {
    idtr.base = &idt[0];
    idtr.limit = idt.len * @sizeOf(idt_entry_t) - 1;

    for (0..256) |index| {
        idt[index] = idt_entry_t{
            .attributes =  0,
            .isr_high =  0,
            .isr_low = 0,
            .kernel_cs = 0,
            .reserved = 0,
    };
    }
    for (0..IDT_MAX_DESCRIPTORS) |index| {
        idt_set_descriptor(
            @intCast(index),
            isr_stub_table[index],
            0x8E
        );
    }
    
    asm volatile (
        \\lidt (%[idt_ptr])
        :
        : [idt_ptr] "r" (&idtr),
    );
    PIC_remap();
    asm volatile ("sti"); // set the interrupt flag
}
