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
    const millis: u32 = sec * 1000 +| nsec / 1000_000;
    const start_time = krn.currentMs();
    krn.task.current.wakeup_time = start_time +| millis;
    krn.task.current.state = .INTERRUPTIBLE_SLEEP;
    krn.sched.reschedule();
    if (krn.task.current.hasPendingSignal()) {
        if (rem) |r| {
            const passed_time = krn.time.kernel_timespec.fromMSec(
                krn.currentMs() - start_time
            );
            r.* = dur.sub(&passed_time);
        }
        return errors.EINTR;
    }
    return 0;
}
