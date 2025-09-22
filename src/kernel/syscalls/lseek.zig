const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

const SEEK_SET = 0;
const SEEK_CUR = 1;
const SEEK_END = 2;

pub fn lseek(fd: u32, offset: u32, whence: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.ops.lseek) |_lseek| {
            return try _lseek(file, offset, whence);
        }
        var new_pos = offset;
        krn.logger.INFO("file descriptor {d}\n", .{fd});
        switch (whence) {
            SEEK_CUR => new_pos = file.pos +| offset,
            SEEK_END => new_pos = file.inode.size +| offset,
            else => {}
        }
        if (new_pos >= file.inode.size) {
            return errors.PosixError.EINVAL;
        }
        file.pos = new_pos;
        return new_pos;
    }
    return errors.PosixError.ENOENT;
}

pub fn llseek(fd: u32, offset_high: u32, offset_low: u32, result: *u64, whence: u32) !u32 {
    _ = offset_high;
    const res = try lseek(fd, offset_low, whence);
    result.* = @intCast(res);
    return res;
}
