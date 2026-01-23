const kernel = @import("kernel");

pub fn kmalloc(size: usize) callconv(.c) usize {
    const addr = kernel.mm.kheap.alloc(size,true, false) catch {
        return 0;
    };
    return addr;
}

pub fn vmalloc(size: usize) callconv(.c) usize {
    const addr = kernel.mm.vheap.alloc(size, false, false) catch {
        return 0;
    };
    return addr;
}

pub fn kfree(address: usize) callconv(.c) void {
    kernel.mm.kheap.free(address);
}

pub fn vfree(address: usize) callconv(.c) void {
    kernel.mm.vheap.free(address);
}
