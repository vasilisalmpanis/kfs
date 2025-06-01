const errors = @import("./error-codes.zig");
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
) i32 {
    krn.logger.INFO("mmap2: {any} {any} {any} flags: {any}", .{
        addr,
        length,
        prot,
        flags,
    });
    if (prot & ~(mm.PROT_EXEC | mm.PROT_READ | mm.PROT_WRITE | mm.PROT_NONE) > 0)
        return -errors.EINVAL;
    // addr specifies the wanted virtual address (suggestion)
    // length is the size of the mapping
    var hint: u32 = @intFromPtr(addr);
    if (addr != null) {
        if (hint & arch.PAGE_SIZE > 0) {
            if (flags.FIXED) {
                return -errors.EINVAL;
            }
            hint &= arch.PAGE_SIZE;
        }
        if (hint < krn.task.current.mm.?.heap)
            hint = krn.task.current.mm.?.heap;
    } else {
        hint = krn.task.current.mm.?.heap;
        krn.logger.INFO("heap_start mmap {x}\n", .{krn.task.current.mm.?.heap});
        // look through mappings and just give back one.
    }
    const area: i32 = krn.task.current.mm.?.mmap_area(hint, arch.pageAlign(length, false), prot, flags);
    const temp: i32 = @intCast(length);
    krn.logger.INFO("allocated area {x}-{x}\n", .{area, area + temp});
    return area;
}
