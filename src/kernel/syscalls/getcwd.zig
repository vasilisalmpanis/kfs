const krn = @import("../main.zig");
const errors = @import("error-codes.zig").PosixError;

pub fn getcwd(buf: ?[*:0]u8, size: usize) !u32 {
    if (buf == null or size < 2) {
        return errors.ERANGE;
    }
    const user_buf = buf.?;
    user_buf[size - 1] = 0;
    const buf_s: [:0]u8 = user_buf[0..size - 1 :0];

    var res = krn.task.current.fs.pwd.getAbsPath(buf_s) catch |err| {
        return switch (err) {
            errors.ERANGE => errors.ERANGE,
            else => errors.EFAULT,
        };
    };

    if (res.len == 0) {
        buf_s[0] = '/';
        buf_s[1] = 0;
        res.len = 1;
    }
    user_buf[res.len] = 0;
    return @intCast(res.len + 1); // For null terminating byte
}
