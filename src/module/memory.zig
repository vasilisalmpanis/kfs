const kernel = @import("kernel");

pub fn kmalloc(size: u32) callconv(.c) u32 {
    const addr = kernel.mm.kheap.alloc(size,true, false) catch {
        return 0;
    };
    return addr;
}

pub fn vmalloc(size: u32) callconv(.c) u32 {
    const addr = kernel.mm.vheap.alloc(size, false, false) catch {
        return 0;
    };
    return addr;
}

pub fn kfree(address: u32) callconv(.c) void {
    kernel.mm.kheap.free(address);
}

pub fn vfree(address: u32) callconv(.c) void {
    kernel.mm.vheap.free(address);
}
