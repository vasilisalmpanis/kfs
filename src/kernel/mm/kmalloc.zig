const mm = @import("init.zig");

// TODO: Fix Alignment for memery returned to 16
/// kmalloc - allocate memory
/// size:
///     how many bytes of memory are required.
pub fn ksize(addr: *anyopaque) u32 {
    return mm.kheap.getSize(@intFromPtr(addr));
}

pub fn kmalloc(comptime T: type) ?*T {
    const size = @sizeOf(T);
    const addr = mm.kheap.alloc(size, true, false) catch return null;
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn kmallocArray(comptime T: type, count: u32) ?[*]T {
    const size = @sizeOf(T) * count;
    const addr = mm.kheap.alloc(size, true, false) catch return null;
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn kfree(addr: *anyopaque) void {
    mm.kheap.free(@intFromPtr(addr));
}

pub fn kmallocSlice(comptime T: type, count: u32) ?[]T {
    const addr = mm.kheap.alloc(count, true, false) catch return null;
    if (addr == 0) return null;
    const ptr: [*]T = @ptrFromInt(addr);
    return ptr[0..count];
}

pub fn dupSlice(comptime T: type, slice: []const T) ?[]T {
    if (kmallocSlice(T, slice.len)) |new| {
        @memcpy(new[0..], slice[0..]);
        return new;
    }
    return null;
}
