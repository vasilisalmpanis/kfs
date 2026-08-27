const arch = @import("arch");
const errors = @import("./error-codes.zig").PosixError;

pub fn sched_getaffinity(pid: u32, cpusetsize: u32, mask: ?[*]u8) !u32 {
    _ = pid;
    const _mask = mask orelse return errors.EFAULT;
    if (cpusetsize < @sizeOf(u32) or cpusetsize % @sizeOf(u32) != 0)
        return errors.EINVAL;
    const ncpus: u32 = @intCast(@max(arch.smp.cpu_count, 1));
    const bytes: u32 = @min(cpusetsize, @sizeOf(u32) * ((ncpus + 31) / 32));
    @memset(_mask[0..bytes], 0);
    var i: u32 = 0;
    while (i < ncpus and i / 8 < bytes) : (i += 1) {
        _mask[i / 8] |= @as(u8, 1) << @intCast(i % 8);
    }
    return bytes;
}
