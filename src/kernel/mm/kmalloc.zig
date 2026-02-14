const mm = @import("init.zig");

// TODO: Fix Alignment for memery returned to 16
/// kmalloc - allocate memory
/// size:
///     how many bytes of memory are required.
pub fn ksize(addr: *anyopaque) usize {
    return mm.kheap.getSize(@intFromPtr(addr));
}

pub fn kmalloc(comptime T: type) ?*T {
    const size = @sizeOf(T);
    const addr = mm.kheap.alloc(size, true, false) catch return null;
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn kmallocArray(comptime T: type, count: usize) ?[*]T {
    const size = @sizeOf(T) * count;
    const addr = mm.kheap.alloc(size, true, false) catch return null;
    if (addr == 0) return null;
    return @ptrFromInt(addr);
}

pub fn kfree(addr: *const anyopaque) void {
    mm.kheap.free(@intFromPtr(addr));
}

pub fn kfreeSlice(slice: anytype) void {
    const Slice = @TypeOf(slice);

    comptime {
        if (@typeInfo(Slice) != .pointer or
            @typeInfo(Slice).pointer.size != .slice)
        {
            @compileError("kfreeSlice expects a slice");
        }
    }

    const ptr = slice.ptr;
    kfree(@ptrCast(ptr));
}

pub fn kmallocSlice(comptime T: type, count: usize) ?[]T {
    const addr = mm.kheap.alloc(count * @sizeOf(T), true, false) catch return null;
    if (addr == 0) return null;
    const ptr: [*]T = @ptrFromInt(addr);
    return ptr[0..count];
}

pub fn kmallocSliceZ(comptime T: type, count: usize) ?[:0]T {
    const addr = mm.kheap.alloc(count * @sizeOf(T) + 1, true, false)
        catch return null;
    if (addr == 0)
        return null;
    const ptr: [*:0]T = @ptrFromInt(addr);
    ptr[count] = 0;
    return ptr[0..count :0];
}

pub fn dupSlice(comptime T: type, slice: []const T) ?[]T {
    if (kmallocSlice(T, slice.len)) |new| {
        @memcpy(new[0..], slice[0..]);
        return new;
    }
    return null;
}

pub fn dupSliceZ(comptime T: type, slice: []const T) ?[:0]T {
    if (kmallocSliceZ(T, slice.len)) |new| {
        @memcpy(new[0..slice.len], slice[0..]);
        return new;
    }
    return null;
}