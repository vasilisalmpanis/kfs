const gdt = @import("arch").gdt;
const cpu = @import("arch").cpu;
const krn = @import("kernel");
const printf = @import("./printf.zig").printf;

pub fn printGDT() void {
    krn.logger.INFO("GDT base: {x} limit: {d}\n", .{gdt.gdt_ptr.ptr().base, gdt.gdt_ptr.ptr().limit});
    krn.logger.INFO("N offset [limit low]    [base low]      [bas mid] [access] [gran] [bas hig]\n", .{});
    for (gdt.gdt_entries.get()) |entry| {
        krn.logger.INFO("{b:0>16} {b:0>16} {b:0>8} {b:0>8} {b:0>8} {b:0>8}\n", .{
            entry.limit_low,
            entry.base_low,
            entry.base_middle,
            entry.access,
            entry.granularity,
            entry.base_high,
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
