const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn read(fd: u32, buf: u32, size: u32) !u32 {
    const data: [*]u8 = @ptrFromInt(buf);
    krn.logger.ERROR("READING FROM {d} {any}\n", .{fd, krn.task.current.files.fds.get(fd)});
    if (krn.task.current.files.fds.get(fd)) |file| {
        return try file.ops.read(file, data, size);
    }
    return errors.PosixError.ENOENT;
}
