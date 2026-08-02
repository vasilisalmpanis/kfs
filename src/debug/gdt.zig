const gdt = @import("arch").gdt;
const cpu = @import("arch").cpu;
const krn = @import("kernel");
const printf = @import("./printf.zig").printf;

pub fn printGDT() void {
    krn.logger.INFO("GDT base: {x} limit: {d}\n", .{gdt.gdt_ptr.ptr().base, gdt.gdt_ptr.ptr().limit});
    krn.logger.INFO("N offset [limit low]    [base low]      [bas mid] [access] [gran] [bas hig]\n", .{});
    const entries = gdt.gdt_entries.ptr();
    const len = gdt.GDT_ENTRIES_COUNT;
    for (0..len) |idx| {
        krn.logger.INFO("{b:0>16} {b:0>16} {b:0>8} {b:0>8} {b:0>8} {b:0>8}\n", .{
            entries[idx].limit_low,
            entries[idx].base_low,
            entries[idx].base_middle,
            entries[idx].access,
            entries[idx].granularity,
            entries[idx].base_high,
        });
    }
}

pub fn printTSS() void {
    const tss: *cpu.TSS = gdt.tss.ptr();
    krn.logger.INFO("TSS base: {x} limit: {x}\n", .{@intFromPtr(tss), @sizeOf(cpu.TSS) - 1});
    krn.logger.INFO("esp0: 0x{x}\nss0: 0x{x}\n", .{
        tss.esp0,
        tss.ss0
    });
    krn.logger.INFO("full tss: {any}\n", .{tss});
}
