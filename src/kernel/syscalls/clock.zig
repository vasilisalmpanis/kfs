const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

const CLOCK_REALTIME			= 0;
const CLOCK_MONOTONIC			= 1;
const CLOCK_PROCESS_CPUTIME_ID= 2;
const CLOCK_THREAD_CPUTIME_ID	= 3;
const CLOCK_MONOTONIC_RAW		= 4;
const CLOCK_REALTIME_COARSE	= 5;
const CLOCK_MONOTONIC_COARSE	= 6;
const CLOCK_BOOTTIME			= 7;
const CLOCK_REALTIME_ALARM	= 8;
const CLOCK_BOOTTIME_ALARM	= 9;

const kernel_timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

pub fn clock_gettime64(clock_id: u32, _tp: ?*kernel_timespec) !u32 {
    const  tp = _tp orelse {
        return errors.EFAULT;
    };
    switch (clock_id) {
        CLOCK_REALTIME => {
            const curr_seconds: u64 = krn.cmos.toUnixSeconds(krn.cmos);
            tp.tv_sec = @intCast(curr_seconds);
            tp.tv_nsec = 0;
            return 0;
        },
        CLOCK_MONOTONIC => {
            const secs = krn.getSecondsFromStart();
            tp.tv_sec = @intCast(secs);
            tp.tv_nsec = 0;
            return 0;
        },
        else => {
            @panic("TODO\n");
        },
    }
    return errors.EINVAL;
}

pub fn clock_settime(clock_id: u32, _tp: ?*kernel_timespec) !u32 {
    const  tp = _tp orelse {
        return errors.EFAULT;
    };
    if (clock_id == CLOCK_REALTIME) {
        krn.cmos.setTime(krn.cmos, @intCast(tp.tv_sec));
        return 0;
    }
    return errors.EINVAL;
}
