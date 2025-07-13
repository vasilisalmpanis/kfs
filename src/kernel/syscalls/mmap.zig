const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const krn = @import("../main.zig");
const mm = @import("../mm/proc_mm.zig");

pub fn mmap2(
    addr: ?*anyopaque,
    length: u32,
    prot: u32,
    flags: mm.MAP,
    _: i32, // fd
    _: u32, // off
) !u32 {
    krn.logger.INFO("mmap2: {any} {any} {any} flags: {any}", .{
        addr,
        length,
        prot,
        flags,
    });
    if (prot & ~(mm.PROT_EXEC | mm.PROT_READ | mm.PROT_WRITE | mm.PROT_NONE) > 0)
        return errors.EINVAL;
    // addr specifies the wanted virtual address (suggestion)
    // length is the size of the mapping
    const len: u32 = arch.pageAlign(length, false);
    var hint: u32 = @intFromPtr(addr);
    if (addr != null) {
        if (hint & (arch.PAGE_SIZE - 1) > 0) {
            if (flags.FIXED) {
                return errors.EINVAL;
            }
            hint = arch.pmm.pageAlign(hint, false);
        }
        if (hint < krn.task.current.mm.?.heap)
            hint = krn.task.current.mm.?.heap;
    } else {
        hint = krn.task.current.mm.?.heap;
        krn.logger.INFO("heap_start mmap {x}\n", .{krn.task.current.mm.?.heap});
        // look through mappings and just give back one.
    }
    return try krn.task.current.mm.?.mmap_area(hint, len, prot, flags);
}
