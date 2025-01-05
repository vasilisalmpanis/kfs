const tty = @import("tty.zig");

pub const GDTEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

pub const GDTPointer = packed struct {
    limit: u16,
    base: usize,
};

const NUM_ENTRIES = 3;

var gdt: [NUM_ENTRIES]GDTEntry = undefined;
var gdt_pointer: GDTPointer = undefined;

fn create_entry(base: u32, limit: u32, access: u8) GDTEntry {
    return GDTEntry{
        .limit_low = @as(u16, @truncate(limit & 0xFFFF)),
        .base_low = @as(u16, @truncate(base & 0xFFFF)),
        .base_mid = @as(u8, @truncate((base >> 16) & 0xFF)),
        .access = access,
        .granularity = @as(u8, @truncate((limit >> 16) & 0x0F | 0xC0)),
        .base_high = @as(u8, @truncate((base >> 24) & 0xFF)),
    };
}

fn load_gdt(ptr: *GDTPointer) void {
    tty.printf("GDT: {}\n", .{ptr});
    return asm volatile ("lgdt (%edi)");
}

pub fn init_gdt() void {
    gdt[0] = create_entry(0, 0, 0); // Null segment
    gdt[1] = create_entry(0, 0xFFFFFFFF, 0x9A); // Code segment
    gdt[2] = create_entry(0, 0xFFFFFFFF, 0x92); // Data segment

    gdt_pointer = GDTPointer{
        .limit = @sizeOf(GDTEntry) * NUM_ENTRIES - 1,
        .base = @intFromPtr(&gdt),
    };

    load_gdt(&gdt_pointer);
}
