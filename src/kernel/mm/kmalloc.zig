const mm = @import("init.zig");
const krn = @import("../main.zig");

// TODO: Fix Alignment for memery returned to 16
/// kmalloc - allocate memory
/// size:
///     how many bytes of memory are required.
pub fn kmalloc(size: u32) u32 {
    krn.logger.INFO("kmalloc: {d}", .{size});
    const res = mm.kheap.alloc(size, true, false) catch 0;
    krn.logger.INFO("kmalloc done: {d}", .{size});
    return res;
}

pub fn kfree(addr: u32) void {
    mm.kheap.free(addr);
}

pub fn ksize(addr: u32) u32 {
    return mm.kheap.getSize(addr);
}
