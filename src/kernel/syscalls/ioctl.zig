const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const errors = @import("error-codes.zig").PosixError;
const drv = @import("drivers");

const FIONBIO: u32 = 0x5421;

pub fn ioctl(fd: u32, op: u32, args: u32) !u32 {
    krn.logger.INFO(
        "ioctl fd: {d}, op: 0x{x}, args: {x}",
        .{fd, op, args}
    );
    if (krn.task.current().files.fds.get(fd)) |file| {
        file.ref.get();
        defer file.ref.put();
        if (op == FIONBIO) {
            const on: ?*const i32 = @ptrFromInt(args);
            const _on = on orelse return errors.EFAULT;
            if (_on.* != 0) {
                file.flags |= krn.fs.file.O_NONBLOCK;
            } else {
                file.flags &= ~@as(@TypeOf(file.flags), krn.fs.file.O_NONBLOCK);
            }
            return 0;
        }
        if (file.ops.ioctl) |_ioctl| {
            return try _ioctl(file, op, args);
        }
        return errors.ENOTTY;
    }
    return errors.EBADF;
}
