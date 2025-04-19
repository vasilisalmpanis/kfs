const errors = @import("../main.zig").errors;
const arch = @import("arch");
const krn = @import("../main.zig");

pub fn mmap2(
    _: *arch.Regs,
    a1: u32,
    a2: u32,
    a3: u32,
    a4: u32,
    a5: u32,
    a6: u32,
) i32 {
    krn.logger.INFO("mmap2: {d} {d} {d} {d} {d} {d}", .{
        a1,
        a2,
        a3,
        a4,
        a5,
        a6,
    });
    return 0;
}
