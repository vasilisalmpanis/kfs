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
};
