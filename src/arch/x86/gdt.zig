
const GDTBASE: u32  =  0x00000800;
const gdtr = packed struct {
    limit: u16,
    base: u32
};

const gdt_entry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle : u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

var gdt_ptr : gdtr = undefined;

// var gdt_entries: [5]gdt_entry = undefined;
pub fn gdt_set_entry(num: u32, base: u32, limit: u32, access: u8, gran: u8) void {
    // load the entry using num as an index into GDTBASE (0x00000800)
    var gdt_temp: *gdt_entry = @ptrFromInt(GDTBASE + (num * @sizeOf(gdt_entry)));
    gdt_temp.base_low = @truncate(base & 0xFFFF);
    gdt_temp.base_middle  = @truncate((base >> 16) & 0xFF);
    gdt_temp.base_high = @truncate((base >> 24) & 0xFF);

    gdt_temp.limit_low = @truncate(limit & 0xFFFF); 
    gdt_temp.granularity = @truncate((limit >> 16) & 0x0F);

    gdt_temp.granularity |= gran & 0xF0; // take the 4 high bits for limit 
    gdt_temp.access = access;
}

pub fn gdt_init() void {
    // @memset(gdt_entries[0..5], 0);
    gdt_ptr.limit = (@sizeOf(gdt_entry) * 5) - 1;
    gdt_ptr.base = GDTBASE;

    gdt_set_entry(0,0,0,0,0); // Null segment
    gdt_set_entry(1, 0, 0xFFFFFFFF, 0x9A, 0xCF); // code segment
    gdt_set_entry(2, 0, 0xFFFFFFFF, 0x92, 0xCF); // data segment
    gdt_set_entry(3, 0, 0xFFFFFFFF, 0xFA, 0xCF); // stack segment
    gdt_set_entry(4, 0, 0xFFFFFFFF, 0xF2, 0xCF); // userspace code
    asm volatile (
        \\lgdt (%edi)
        \\jmp $0x08, $.reload_CS
        \\.reload_CS:
        \\mov $0x10, %ax
        \\mov %ax, %ds
        \\mov %ax, %es
        \\mov %ax, %ss
        \\mov %ax, %fs
        \\mov %ax, %gs
        :
        : [ptr] "{edi}" (&gdt_ptr),
        : "rax"
    );
}

