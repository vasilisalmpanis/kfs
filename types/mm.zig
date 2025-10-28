const types = @import("types.zig");

pub fn kmalloc(comptime T: type) ?*T {
    const size = @sizeOf(T);
    const addr = types.api.kheap_alloc(size, true, false);
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn kmallocArray(comptime T: type, count: u32) ?[*]T {
    const size = @sizeOf(T) * count;
    const addr = types.api.kheap_alloc(size, true, false);
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn kmallocSlice(comptime T: type, count: u32) ?[]T {
    const addr = types.api.kheap_alloc(count * @sizeOf(T), true, false);
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

pub fn kfree(addr: *anyopaque) void {
    types.api.kheap_free(@intFromPtr(addr));
}
