const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn read(fd: u32, buf: u32, size: u32) !u32 {
    const data: [*]u8 = @ptrFromInt(buf);
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (!file.canRead())
            return errors.PosixError.EACCES;
        return try file.ops.read(file, data, size);
    }
    return errors.PosixError.ENOENT;
}
