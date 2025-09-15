const cpu = @import("./system/cpu.zig");
const idt = @import("./idt.zig");

pub const GDTBASE: u32  =  0xC0000800;
const Gdtr = packed struct {
    limit: u16,
    base: u32
};

pub const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle : u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

pub var gdt_ptr : Gdtr = undefined;

pub const GDT_TLS0_INDEX: u32 = 6;
pub const GDT_TLS1_INDEX: u32 = 7;
pub const GDT_TLS2_INDEX: u32 = 8;

pub fn gdtSetEntry(num: u32, base: u32, limit: u32, access: u8, gran: u8) void {
    // load the entry using num as an index into GDTBASE (0x00000800)
    var gdt_temp: *GdtEntry = @ptrFromInt(GDTBASE + (num * @sizeOf(GdtEntry)));
    gdt_temp.base_low = @truncate(base & 0xFFFF);
    gdt_temp.base_middle  = @truncate((base >> 16) & 0xFF);
    gdt_temp.base_high = @truncate((base >> 24) & 0xFF);

    gdt_temp.limit_low = @truncate(limit & 0xFFFF); 
    gdt_temp.granularity = @truncate((limit >> 16) & 0x0F);

    gdt_temp.granularity |= gran & 0xF0; // take the 4 high bits for limit 
    gdt_temp.access = access;
}

extern const stack_top: u32;
pub var tss: cpu.TSS = cpu.TSS.init();

pub fn gdtInit() void {
    tss.ss0 = idt.KERNEL_DATA_SEGMENT;
    tss.esp0 = @intFromPtr(&stack_top);

    gdt_ptr.limit = (@sizeOf(GdtEntry) * 9) - 1;
    gdt_ptr.base = GDTBASE;

    gdtSetEntry(0,0,0,0,0);                    // Null segment
    gdtSetEntry(1, 0, 0xFFFFFFFF, 0x9A, 0xCF); // Kernel code
    gdtSetEntry(2, 0, 0xFFFFFFFF, 0x92, 0xCF); // Kernel data
    gdtSetEntry(3, 0, 0xFFFFFFFF, 0xFA, 0xCF); // userspace code
    gdtSetEntry(4, 0, 0xFFFFFFFF, 0xF2, 0xCF); // userspace data
    gdtSetEntry(5, @intFromPtr(&tss), @sizeOf(cpu.TSS) - 1, 0x89, 0x00); // userspace stack

    gdtSetEntry(GDT_TLS0_INDEX, 0, 0, 0x72, 0x00);
    gdtSetEntry(GDT_TLS1_INDEX, 0, 0, 0x72, 0x00);
    gdtSetEntry(GDT_TLS2_INDEX, 0, 0, 0x72, 0x00);

    asm volatile (
        \\  lgdt (%edi)
        \\  jmp $0x08, $.reload_CS
        \\.reload_CS:
        \\  mov $0x10, %ax
        \\  mov %ax, %ds
        \\  mov %ax, %es
        \\  mov %ax, %ss
        \\  mov %ax, %fs
        \\  mov %ax, %gs
        :
        : [ptr] "{edi}" (&gdt_ptr),
        : .{ .eax = true}
    );
    asm volatile (
        \\ mov $(8 * 5), %ax
        \\ ltr %ax
    );
}
