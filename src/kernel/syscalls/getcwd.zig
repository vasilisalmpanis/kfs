const krn = @import("../main.zig");
const errors = @import("error-codes.zig").PosixError;

pub fn getcwd(buf: ?[*:0]u8, size: usize) !u32 {
    if (buf == null or size < 2) {
        return errors.ERANGE;
    }
    const user_buf = buf.?;
    const buf_s = user_buf[0..size - 1];
    buf_s[0] = '/';
    buf_s[1] = 0;
    const res = krn.task.current.fs.pwd.getAbsPath(buf_s) catch {
        return errors.EFAULT;
    };
    if (res.len > 0)
        buf_s[res.len] = 0;
    return @intFromPtr(res.ptr);
}
