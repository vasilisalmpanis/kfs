const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn write(fd: u32, buf: u32, size: u32) !u32 {
    const data: [*]u8 = @ptrFromInt(buf);
    if (fd == 2) {
        krn.serial.print(data[0..size]);
    } else if (fd == 1) {
        dbg.printf("{s}", .{data[0..size]});
    } else {
        // This should be the real write for all the fds
        if (krn.task.current.files.fds.get(fd)) |file| {
            return try file.ops.write(file, data, size);
        }
        return errors.PosixError.ENOENT;
    }
    return @intCast(size);
}

pub const IoVec = extern struct {
    base: [*]u8,
    len: usize,
};

pub fn writev(fd: u32, iov: [*]IoVec, iovcnt: u32) !u32 {
    var ret: u32 = 0;
    for (0..iovcnt) |idx| {
        const curr = iov[idx];
        if (curr.len > 0)
            ret += try write(
                fd,
                @intFromPtr(curr.base),
                curr.len
            );
    }
    return ret;
}

pub fn pwritev(fd: u32, iov: [*]IoVec, iovcnt: u32, offset: u32) !u32 {
    _ = offset;
    return try writev(fd, iov, iovcnt);
}
