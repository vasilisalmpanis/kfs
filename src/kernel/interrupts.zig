const tty = @import("tty.zig");


const idt_entry_t = packed struct {
    isr_low: u16, // The lower 16 bits of the ISR's address
    kernel_cs: u16, // The GDT segment selector that the CPU will load into CS before calling the ISR
    reserved: u8, // Set to zero
    attributes: u8, // Type and attributes; see the IDT page
    isr_high: u16, // The higher 16 bits of the ISR's address
};

const IDT_MAX_DESCRIPTORS: u16 = 256;
const idtr_t = packed struct {
    limit: u16,
    base: u32,
};

pub export fn exception_handler(
    exception_number: u32,
    stack_pointer: usize
) noreturn {
    tty.printf(
        "interrupt {d} {x}\n",
        .{exception_number, stack_pointer}
    );
    asm volatile ("cli; hlt");
    while (true) {}
}
pub var idt: [256]idt_entry_t = undefined;

pub var idtr: idtr_t align(0x10) = undefined;

pub var vectors: [IDT_MAX_DESCRIPTORS]bool = undefined;

extern const isr_stub_table: [256]*void;


pub fn idt_set_descriptor(vector: u8, isr: *void, flags: u8) void {
    var descriptor: *idt_entry_t = &idt[vector];

    descriptor.isr_low = @as(u16, @truncate(@intFromPtr(isr) & 0xFFFF));
    descriptor.kernel_cs = 0x08; // this value can be whatever offset your kernel code selector is in your GDT
    descriptor.attributes = flags;
    descriptor.isr_high = @as(u16, @truncate(@intFromPtr(isr) >> 16));
    descriptor.reserved = 0;
}

pub fn idt_init() void {
    idtr.base = @intFromPtr(&idt[0]);
    idtr.limit = @as(u16, @sizeOf(idt_entry_t)) * IDT_MAX_DESCRIPTORS - 1;

    var index: u8 = 0;
    while (index < 32) : (index += 1) {
        idt_set_descriptor(index, isr_stub_table[index], 0x8E);
        vectors[index] = true;
    }
    // asm volatile ("lidt [$0]"(idtr));
    asm volatile (
        \\lidt (%[idt_ptr])
        :
        : [idt_ptr] "r" (&idtr),
    );

    // Set the interrupt flag (enable interrupts)
    asm volatile ("sti");
    // tty.printf("idt: {any}\n", .{idt});
    tty.printf("idtr: {any}\n", .{idtr});
}
