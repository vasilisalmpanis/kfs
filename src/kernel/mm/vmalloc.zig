const mm = @import("init.zig");

pub fn vmalloc(size: usize) usize {
    return mm.vheap.alloc(size, false, false) catch 0;
}

pub fn vmallocArray(comptime T: type, count: usize) ?[*]T {
    const size = @sizeOf(T) * count;
    const addr = mm.vheap.alloc(size, false, false) catch return null;
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn vmallocSlice(comptime T: type, count: usize) ?[]T {
    const addr = mm.vheap.alloc(count * @sizeOf(T), false, false) catch return null;
    if (addr == 0) return null;
    const ptr: [*]T = @ptrFromInt(addr);
    return ptr[0..count];
}

pub fn vfree(ptr: *const anyopaque) void {
    const addr: u32 = @intFromPtr(ptr);
    if (addr == 0)
        return;
    mm.vheap.free(addr);
}

pub fn vfreeSlice(slice: anytype) void {
    const Slice = @TypeOf(slice);

    comptime {
        if (@typeInfo(Slice) != .pointer or
            @typeInfo(Slice).pointer.size != .slice)
        {
            @compileError("kfreeSlice expects a slice");
        }
    }

    const ptr = slice.ptr;
    vfree(@ptrCast(ptr));
}

pub fn vsize(addr: usize) usize {
    return mm.vheap.getSize(addr);
}
