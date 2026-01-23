const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

const SEEK_SET = 0;
const SEEK_CUR = 1;
const SEEK_END = 2;

pub fn lseek(fd: u32, offset: isize, whence: u32) !usize {
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.ops.lseek) |_lseek| {
            return try _lseek(file, offset, whence);
        }
        var new_pos: i64 = @intCast(offset);
        switch (whence) {
            SEEK_CUR => new_pos = @as(i64, @intCast(file.pos)) + offset,
            SEEK_END => new_pos = @as(i64, @intCast(file.inode.size)) + offset,
            else => {}
        }
        if (new_pos < 0 or new_pos > file.inode.size)
            return errors.PosixError.EINVAL;
        file.pos = @intCast(new_pos);
        return file.pos;
    }
    return errors.PosixError.ENOENT;
}

pub fn llseek(fd: u32, offset_high: u32, offset_low: u32, result: *u64, whence: u32) !usize{
    const offset: i64 = @as(i64 , @intCast(offset_high)) << 32 | @as(i64, @intCast(offset_low));
    const res = try lseek(fd, @intCast(offset), whence);
    result.* = @intCast(res);
    return 0;
}
