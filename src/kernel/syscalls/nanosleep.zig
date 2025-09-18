const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

const Timespec = extern struct {
    tv_sec: i32,
    tv_nsec: i32,
};

pub fn nanosleep(req: ?*Timespec, rem: ?*Timespec) !u32 {
    if (req == null)
        return errors.EINVAL;
    const ns_total: i64 = @as(i64, req.?.tv_sec) * 1000000000
        + @as(i64, req.?.tv_nsec);
    if (ns_total <= 0)
        return 0;

    const ms: u64 = @intCast(@divTrunc(
        ns_total + 999999,
        @as(i64, 1000000)
    ));
    krn.logger.DEBUG(
        "nanosleep req {d}s {d}ns, total {d}ms",
        .{req.?.tv_sec, req.?.tv_nsec, ms}
    );
    krn.sleep(@intCast(ms));

    if (rem) |_rem| {
        const zero = Timespec{ 
            .tv_sec = 0,
            .tv_nsec = 0
        };
        _rem.* = zero;
    }
    return 0;
}
