const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig").PosixError;
const drv = @import("drivers");

pub fn ioctl(fd: u32, op: u32, args: ?*anyopaque) !u32 {
    krn.logger.INFO(
        "ioctl fd: {d}, op: 0x{x}, args: {x}",
        .{fd, op, @intFromPtr(args)}
    );
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.ops.ioctl) |_ioctl| {
            return try _ioctl(file, op, args);
        }
        return errors.ENOTTY;
    }
    return errors.EBADF;
}
