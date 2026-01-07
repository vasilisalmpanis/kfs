const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

pub fn nanosleep(
    duration: ?*krn.kernel_timespec,
    rem: ?*krn.kernel_timespec,
) !u32 {
    if (duration == null)
        return errors.EFAULT;
    var dur: krn.kernel_timespec = duration.?.*;
    if (!dur.isValid())
        return errors.EINVAL;
    const sec: u32 = @intCast(dur.tv_sec);
    const nsec: u32 = @intCast(dur.tv_nsec);
    const millis: u32 = sec * 1000 +| nsec / 1000;
    const start_time = krn.currentMs();
    krn.task.current.wakeup_time = start_time +| millis;
    krn.task.current.state = .INTERRUPTIBLE_SLEEP;
    krn.sched.reschedule();
    if (krn.task.current.sighand.hasPending()) {
        if (rem) |r| {
            const passed_millis: i32 = @intCast(krn.currentMs() - start_time);
            const passed_nanos: i32 = @rem(passed_millis, 1000) * 1000;
            r.tv_sec = dur.tv_sec - @divTrunc(passed_millis, 1000);
            r.tv_nsec = dur.tv_nsec - passed_nanos;
        }
        return errors.EINTR;
    }
    return 0;
}
