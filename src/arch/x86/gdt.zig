const cpu = @import("./system/cpu.zig");
const idt = @import("./idt.zig");
const percpu = @import("./smp/percpu.zig");

pub const GDTBASE: u32  =  0xC0000800;

pub const GDT_ENTRIES_COUNT: u32 = 10;

pub const gdt_ptr = percpu.PerCpu(Gdtr, Gdtr{}, opaque {});
pub const tss = percpu.PerCpu(cpu.TSS, cpu.TSS.init(), opaque {});
pub const gdt_entries = percpu.PerCpu(
    [GDT_ENTRIES_COUNT]GdtEntry,
    undefined,
    opaque {}
);

pub const Gdtr = packed struct {
    limit: u16 = 0,
    base: u32 = 0,
};

pub const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle : u8,
    access: u8,
    granularity: u8,
    base_high: u8,

    pub fn set(self: *GdtEntry, base: u32, limit: u32, access: u8, gran: u8) void {
        self.base_low = @truncate(base & 0xFFFF);
        self.base_middle  = @truncate((base >> 16) & 0xFF);
        self.base_high = @truncate((base >> 24) & 0xFF);

        self.limit_low = @truncate(limit & 0xFFFF); 
        self.granularity = @truncate((limit >> 16) & 0x0F);

        self.granularity |= gran & 0xF0; // take the 4 high bits for limit 
        self.access = access;
    }
};


pub const GDT_TLS0_INDEX: u32 = 6;
pub const GDT_TLS1_INDEX: u32 = 7;
pub const GDT_TLS2_INDEX: u32 = 8;
pub const GDT_PERCPU_INDEX: u32 = 9;

pub const GS_OFFSET: u32 = GDT_PERCPU_INDEX * @sizeOf(GdtEntry);


extern const bsp_stack_top: u32;
extern const _percpu_start: u32;
extern const _percpu_end: u32;

pub fn gdtInit(
    gdtr: *Gdtr,
    tss_ptr: *cpu.TSS,
    percpu_addr: u32,
    percpu_size: u32,
    gdt_entries_ptr: *[GDT_ENTRIES_COUNT]GdtEntry,
) void {
    gdtr.limit = (@sizeOf(GdtEntry) * GDT_ENTRIES_COUNT) - 1;
    gdtr.base = @intFromPtr(gdt_entries_ptr);


    gdt_entries_ptr[0].set(0,0,0,0);                    // Null segment
    gdt_entries_ptr[1].set(0, 0xFFFFFFFF, 0x9A, 0xCF); // Kernel code
    gdt_entries_ptr[2].set(0, 0xFFFFFFFF, 0x92, 0xCF); // Kernel data
    gdt_entries_ptr[3].set(0, 0xFFFFFFFF, 0xFA, 0xCF); // userspace code
    gdt_entries_ptr[4].set(0, 0xFFFFFFFF, 0xF2, 0xCF); // userspace data
    gdt_entries_ptr[5].set(@intFromPtr(tss_ptr), @sizeOf(cpu.TSS) - 1, 0x89, 0x00); // userspace stack

    gdt_entries_ptr[GDT_TLS0_INDEX].set(0, 0, 0x72, 0x00);
    gdt_entries_ptr[GDT_TLS1_INDEX].set(0, 0, 0x72, 0x00);
    gdt_entries_ptr[GDT_TLS2_INDEX].set(0, 0, 0x72, 0x00);
    gdt_entries_ptr[GDT_PERCPU_INDEX].set(
        percpu_addr,
        percpu_size,
        0x92,
        0b0100_0000
    );

    asm volatile (
        \\  lgdt (%edi)
        \\  jmp $0x08, $1f
        \\1:
        \\  mov $0x10, %ax
        \\  mov %ax, %ds
        \\  mov %ax, %es
        \\  mov %ax, %ss
        \\  mov %ax, %fs
        \\  mov %[gs_offset], %ax
        \\  mov %ax, %gs
        :
        : [ptr] "{edi}" (gdtr),
          [gs_offset] "r" (@as(u16, @intCast(GS_OFFSET))),
        : .{ .eax = true }
    );
    asm volatile (
        \\ mov $(8 * 5), %ax
        \\ ltr %ax
        ::: .{ .eax = true, .memory = true }
    );
}

pub fn init() void {
    percpu.percpu_start_addr = @intFromPtr(&percpu._percpu_start);
    percpu.percpu_end_addr = @intFromPtr(&percpu._percpu_end);
    const tss_ptr = tss.getRawPtr();
    tss_ptr.ss0 = idt.KERNEL_DATA_SEGMENT;
    gdtInit(
        gdt_ptr.getRawPtr(),
        tss_ptr,
        percpu.percpu_start_addr,
        percpu.percpu_end_addr - percpu.percpu_start_addr,
        gdt_entries.getRawPtr(),
    );
    tss_ptr.esp0 = @intFromPtr(&bsp_stack_top);
}
