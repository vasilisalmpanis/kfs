const mm = @import("init.zig");

pub fn vmalloc(size: usize) usize {
    return mm.vheap.alloc(size, false, false) catch 0;
}

pub fn vfree(addr: usize) void {
    mm.vheap.free(addr);
}

pub fn vsize(addr: usize) usize {
    return mm.vheap.getSize(addr);
}
