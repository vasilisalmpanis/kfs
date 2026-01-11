const std = @import("std");
const krn = @import("../main.zig");

pub const RingBuf = struct {
    buf: []u8,
    mask: usize,
    r: usize = 0,
    w: usize = 0,
    line_count: u32 = 0,

    fn _init(buff: []u8) !RingBuf {
        if (buff.len == 0 or (buff.len & (buff.len - 1)) != 0) {
            krn.logger.ERROR("RingBuf buffer length must be power of two, got {d}\n", .{ buff.len });
            return krn.errors.PosixError.EINVAL;
        }
        return RingBuf{
            .buf = buff,
            .mask = buff.len - 1
        };
    }

    pub fn new(size: usize) !RingBuf {
        if (size == 0) {
            return krn.errors.PosixError.EINVAL;
        }
        var _size = size;
        if ((size & (size - 1)) != 0) {
            _size = (@as(usize, 1) << @truncate(std.math.log2_int_ceil(usize, size)));
        }
        if (krn.mm.kmallocSlice(u8, _size)) |buf| {
            errdefer krn.mm.kfree(buf.ptr);
            return try RingBuf._init(buf);
        }
        return krn.errors.PosixError.ENOMEM;
    }

    pub fn deinit(self: *RingBuf) void {
        krn.mm.kfree(self.buf.ptr);
        self.* = .{
            .buf = self.buf[0..0],
            .mask = 0,
            .r = 0,
            .w = 0,
            .line_count = 0,
        };
    }

    pub inline fn capacity(self: *const RingBuf) usize {
        return self.buf.len;
    }

    pub inline fn len(self: *const RingBuf) usize {
        return (self.w + self.buf.len - self.r) & self.mask;
    }

    pub inline fn available(self: *const RingBuf) usize {
        return self.len();
    }

    pub inline fn isEmpty(self: *const RingBuf) bool {
        return self.r == self.w;
    }

    pub inline fn isFull(self: *const RingBuf) bool {
        return ((self.w + 1) & self.mask) == self.r;
    }

    pub inline fn freeSpace(self: *const RingBuf) usize {
        return self.buf.len - 1 - self.len();
    }

    pub fn reset(self: *RingBuf) usize {
        const dropped = self.len();
        self.r = 0;
        self.w = 0;
        self.line_count = 0;
        return dropped;
    }

    pub fn push(self: *RingBuf, b: u8) bool {
        if (self.isFull()) return false;
        self.buf[self.w] = b;
        self.w = (self.w + 1) & self.mask;
        if (b == '\n') self.line_count += 1;
        return true;
    }

    pub fn pushSlice(self: *RingBuf, src: []const u8) usize {
        var i: usize = 0;
        while (i < src.len and !self.isFull()) : (i += 1) {
            _ = self.push(src[i]);
        }
        return i;
    }

    pub fn unwrite(self: *RingBuf, n: usize) usize {
        var undone: usize = 0;
        while (undone < n and self.w != self.r) {
            const prev = (self.w + self.buf.len - 1) & self.mask;
            if (self.buf[prev] == '\n') break;
            self.w = prev;
            undone += 1;
        }
        return undone;
    }

    pub fn pop(self: *RingBuf) ?u8 {
        if (self.isEmpty()) return null;
        const b = self.buf[self.r];
        self.r = (self.r + 1) & self.mask;
        if (b == '\n' and self.line_count > 0) self.line_count -= 1;
        return b;
    }

    pub fn readInto(self: *RingBuf, dst: []u8) usize {
        var i: usize = 0;
        while (i < dst.len) {
            const v = self.pop() orelse break;
            dst[i] = v;
            i += 1;
        }
        return i;
    }

    pub inline fn hasLine(self: *const RingBuf) bool {
        return self.line_count > 0;
    }

    pub fn peekLineLen(self: *const RingBuf) ?usize {
        if (self.line_count == 0) return null;
        var i = self.r;
        var count: usize = 0;
        while (i != self.w) : (i = (i + 1) & self.mask) {
            if (self.buf[i] == '\n')
                return count + 1;
            count += 1;
        }
        return null;
    }

    pub fn readLineInto(self: *RingBuf, dst: []u8) usize {
        const ll = self.peekLineLen() orelse return 0;
        const take = @min(ll, dst.len);
        var i = self.r;
        var n: usize = 0;
        while (n < take) : (n += 1) {
            dst[n] = self.buf[i];
            i = (i + 1) & self.mask;
        }
        self.r = (self.r + take) & self.mask;
        if (take >= ll and self.line_count > 0) self.line_count -= 1;
        return take;
    }

    pub fn readableSlices(self: *const RingBuf) [2][]const u8 {
        if (self.isEmpty()) return .{ self.buf[0..0], self.buf[0..0] };
        if (self.r < self.w) return .{ self.buf[self.r..self.w], self.buf[0..0] };
        return .{ self.buf[self.r..self.buf.len], self.buf[0..self.w] };
    }
};
