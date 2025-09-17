const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn ioctl(fd: u32, op: u32, data: ?*anyopaque) !u32 {
    krn.logger.DEBUG("ioctl fd {d}, op {x}, data {x}", .{fd, op, @intFromPtr(data)});
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.path == null) {
            krn.logger.ERROR("ioctl {d} has no path, op: {x}", .{fd, op});
            return errors.PosixError.ENOTTY;
        }
        if (file.ops.ioctl) |_ioctl| {
            return try _ioctl(file, op, data);
        } else {
            krn.logger.ERROR("ioctl {d} has no ioctl: ENOTTY", .{fd});
            return errors.PosixError.ENOTTY;
        }
    }
    krn.logger.ERROR("ioctl bad fd {d}", .{fd});
    return errors.PosixError.EBADF;
}
