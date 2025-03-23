const mm = @import("init.zig");

pub fn vmalloc(size: u32) u32 {
    return mm.vheap.alloc(size, false, false) catch 0;
}

pub fn vfree(addr: u32) void {
    mm.vheap.free(addr);
}

pub fn vsize(addr: u32) u32 {
    return mm.vheap.getSize(addr);
}
