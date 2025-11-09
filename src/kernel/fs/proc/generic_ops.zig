const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");
const interface = @import("interface.zig");
const std = @import("std");

// Generic

const Slice = struct {
    ptr: *anyopaque,
    len: u32,
};

pub fn generic_close(base: *kernel.fs.File) void {
    if (base.data == null)
        return ;
    const slice: *Slice = @ptrCast(@alignCast(base.data));
    kernel.mm.kfree(slice.ptr);
    kernel.mm.kfree(base.data.?);
}

pub fn generic_write(_: *kernel.fs.File, _: [*]const u8, _: u32) anyerror!u32 {
    return kernel.errors.PosixError.ENOSYS;
}

pub fn generic_read(base: *kernel.fs.File, buf: [*]u8, size: u32) anyerror!u32 {
    if (base.data == null)
        return 0;

    const content: *[]const u8 = @ptrCast(@alignCast(base.data));
    var to_read: u32 = size;
    if (base.pos >= content.len)
        return 0;
    if (base.pos + to_read > content.len) {
        to_read = content.len - base.pos;
    }
    @memcpy(buf[0..to_read], content.*[base.pos..base.pos + to_read]);
    base.pos += to_read;
    return to_read;
}

pub inline fn assignSlice(file: *fs.File, content: []u8) !void {
        const slice = kernel.mm.kmalloc(Slice) orelse {
            return kernel.errors.PosixError.ENOMEM;
        };
        slice.ptr = content.ptr;
        slice.len = content.len;
        file.data = slice;
}
