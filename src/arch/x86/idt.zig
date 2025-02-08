const context = @import("./context.zig");
const printf = @import("debug").printf;
const IDT_MAX_DESCRIPTORS = 32;
const idt_entry_t = packed struct {
    isr_low: u16,       // The lower 16 bits of the ISR's address
    kernel_cs: u16,     // The GDT segment selector that the CPU will load into CS before calling the ISR
    reserved: u8,       // Set to zero
    attributes: u8,     // Type and attributes; see the IDT page
    isr_high: u16,      // The higher 16 bits of the ISR's address
};

const  idtr_t = packed struct {
    limit: u16,
    base: *const idt_entry_t,
};

var idt: [256] idt_entry_t align(0x10) = undefined;
var idtr: idtr_t = undefined;

pub export fn exception_handler(entry: u8, err_code: u32) callconv(.C) void {
    // _ = entry;
    // _ = ctx;
    printf("entry: {x}, err_code: {b}\n", .{entry, err_code});
    // while (true) {}
}

pub fn idt_set_descriptor(vector: u8, isr: *void, flags: u8) void {
    const descriptor: *idt_entry_t = &idt[vector];

    descriptor.isr_low        = @as(u16, @truncate(@intFromPtr(isr) & 0xFFFF));
    descriptor.kernel_cs      = 0x08; // this value can be whatever offset your kernel code selector is in your GDT
    descriptor.attributes     = flags;
    descriptor.isr_high       = @as(u16, @truncate(@intFromPtr(isr) >> 16));
    descriptor.reserved       = 0;
}

extern const isr_stub_table: [32]*void;

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
        idt_set_descriptor(@intCast(index) , isr_stub_table[index], 0x8E);
        // vectors[vector] = true;
    }

    asm volatile (
        \\lidt (%[idt_ptr])
        :
        : [idt_ptr] "r" (&idtr),
    );
    asm volatile ("sti"); // set the interrupt flag
    // asm volatile (
        // \\ xor %eax, %eax
        // \\ idiv %eax, %eax
    // );
}
