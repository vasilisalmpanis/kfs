const mm = @import("init.zig");

// TODO: Fix Alignment for memery returned to 16
/// kmalloc - allocate memory
/// size:
///     how many bytes of memory are required.
pub fn kmalloc(size: u32) u32 {
    return mm.kheap.alloc(size, true, false) catch 0;
}

pub fn kfree(addr: u32) void {
    mm.kheap.free(addr);
}

pub fn ksize(addr: u32) u32 {
    return mm.kheap.getSize(addr);
}
