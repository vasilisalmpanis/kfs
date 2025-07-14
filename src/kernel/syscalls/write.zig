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
