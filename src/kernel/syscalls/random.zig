const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;

const GRND_NONBLOCK: u32 = 1;
const GRND_RANDOM: u32 = 2;
const GRND_INSECURE: u32 = 4;

pub fn getrandom(buf: ?[*]u8, len: u32, flags: u32) !u32 {
    if (flags & ~(GRND_NONBLOCK | GRND_RANDOM | GRND_INSECURE) != 0)
        return errors.EINVAL;
    const _buf = buf orelse return errors.EFAULT;
    if (len == 0) return 0;
    krn.random.fill(_buf[0..len]);
    return len;
}
