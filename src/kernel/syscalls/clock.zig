const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

const kernel_timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};
pub fn clock_gettime64(clock_id: u32, _tp: ?*kernel_timespec) !u32 {
    const  tp = _tp orelse {
        return errors.EFAULT;
    };
    _ = clock_id;
    const curr_seconds: u64 = krn.cmos.toUnixSeconds(krn.cmos);
    tp.tv_sec = @intCast(curr_seconds);
    tp.tv_nsec = 0;
    return 0;
}
