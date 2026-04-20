const krn = @import("../main.zig");

pub const UTIME_NOW = 0x3fffffff;
pub const UTIME_OMIT = 0x3ffffffe;

pub const kernel_timespec = extern struct {
    tv_sec: i32,
    tv_nsec: i32,

    pub inline fn isValid(self: *const kernel_timespec) bool {
        if (self.tv_sec < 0)
            return false;
        if (self.tv_nsec == UTIME_NOW or self.tv_nsec == UTIME_OMIT)
            return true;
        return self.tv_nsec >= 0 and self.tv_nsec <= 999999999;
    }

    pub inline fn isNow(self: *const kernel_timespec) bool {
        return self.tv_nsec == UTIME_NOW;
    }

    pub inline fn isOmit(self: *const kernel_timespec) bool {
        return self.tv_nsec == UTIME_OMIT;
    }

    pub inline fn fromMSec(ms: u64) kernel_timespec {
        return kernel_timespec{
            .tv_sec =  @intCast(@divTrunc(ms, 1000)),
            .tv_nsec = @intCast(@rem(ms, 1000) * 1000_000),
        };
    }

    pub inline fn sub(
        self: *const kernel_timespec,
        other: *const kernel_timespec
    ) kernel_timespec {
        var res = self.*;
        res.tv_sec -= other.tv_sec;
        if (other.tv_nsec > res.tv_nsec) {
            res.tv_sec -= 1;
            res.tv_nsec = 1_000_000_000 - (other.tv_nsec - res.tv_nsec);
        } else {
            res.tv_nsec -= other.tv_nsec;
        }
        return res;
    }
};

pub const kernel_timespec64 = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};
