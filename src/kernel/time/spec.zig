pub const UTIME_NOW = 0x3fffffff;
pub const UTIME_OMIT = 0x3ffffffe;

pub const kernel_timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,

    pub inline fn isValid(self: *kernel_timespec) bool {
        if (self.tv_nsec == UTIME_NOW or self.tv_nsec == UTIME_OMIT)
            return true;
        return self.tv_nsec >= 0 and self.tv_nsec <= 999999999;
    }

    pub inline fn isNow(self: *kernel_timespec) bool {
        return self.tv_nsec == UTIME_NOW;
    }

    pub inline fn isOmit(self: *kernel_timespec) bool {
        return self.tv_nsec == UTIME_OMIT;
    }
};
