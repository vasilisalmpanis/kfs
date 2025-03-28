const gdt = @import("arch").gdt;
const cpu = @import("arch").cpu;
const krn = @import("kernel");
const printf = @import("./printf.zig").printf;

pub fn printGDT() void {
    krn.logger.INFO("GDT base: {x} limit: {d}\n", .{gdt.gdt_ptr.base, gdt.gdt_ptr.limit});
    krn.logger.INFO("N offset [limit low]    [base low]      [bas mid] [access] [gran] [bas hig]\n", .{});
    for (0..6) |i| {
        const gdt_temp: *gdt.GdtEntry = @ptrFromInt(gdt.GDTBASE + (i * @sizeOf(gdt.GdtEntry)));
        krn.logger.INFO("{d} {x:>2}: {b:0>16} {b:0>16} {b:0>8} {b:0>8} {b:0>8} {b:0>8}\n", .{
            i,
            @intFromPtr(gdt_temp) - gdt.GDTBASE,
            gdt_temp.limit_low,
            gdt_temp.base_low,
            gdt_temp.base_middle,
            gdt_temp.access,
            gdt_temp.granularity,
            gdt_temp.base_high,
        });
    }
    krn.logger.INFO("\n", .{});
    for (0..6) |i| {
        const gdt_temp: *gdt.GdtEntry = @ptrFromInt(gdt.GDTBASE + (i * @sizeOf(gdt.GdtEntry)));
        krn.logger.INFO("{d} {x:>2}: {x:0>4} {x:0>4} {x:0>2} {x:0>2} {x:0>2} {x:0>2}\n", .{
            i,
            @intFromPtr(gdt_temp) - gdt.GDTBASE,
            gdt_temp.limit_low,
            gdt_temp.base_low,
            gdt_temp.base_middle,
            gdt_temp.access,
            gdt_temp.granularity,
            gdt_temp.base_high,
        });
    }
}

pub fn printTSS() void {
    const tss: *cpu.TSS = &gdt.tss;
    krn.logger.INFO("TSS base: {x} limit: {x}\n", .{@intFromPtr(tss), @sizeOf(cpu.TSS) - 1});
    krn.logger.INFO("esp0: 0x{x}\nss0: 0x{x}\n", .{
        tss.esp0,
        tss.ss0
    });
    krn.logger.INFO("full tss: {any}\n", .{tss});
}
