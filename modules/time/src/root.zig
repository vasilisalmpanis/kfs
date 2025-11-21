
const std = @import("std");
const kfs = @import("kfs");
const api = kfs.api;
const krn = kfs.kernel;

pub fn panic(
    msg: []const u8,
    _: ?*std.builtin.StackTrace,
    _: ?usize
) noreturn {
    api.module_panic(msg.ptr, msg.len);
    while (true) {}
}

pub const CMOS_ADDRESS = 0x70;
pub const CMOS_DATA = 0x71;

pub fn initCMOS() kfs.drivers.cmos.CMOS {
    var _cmos= kfs.drivers.cmos.CMOS{
        .curr_time = .{0} ** 7,
        .updateTime = updateTime,
        .incSec = incSec,
        .toUnixSeconds = toUnixSeconds,
        .setTime = setTime,
    };
    _cmos.updateTime(&_cmos);
    return _cmos;
}

pub fn readByte(reg: u8) u8 {
    kfs.arch.io.outb(CMOS_ADDRESS, reg);
    return kfs.arch.io.inb(CMOS_DATA);
}

pub fn writeByte(reg: u8, value: u8) void {
    kfs.arch.io.outb(CMOS_ADDRESS, reg);
    kfs.arch.io.outb(CMOS_DATA, value);
}

fn updateInProgress() bool {
    writeByte(CMOS_ADDRESS, 0x0A);
    return (readByte(0x0B) & 0x80) != 0;
}

fn updateTime(self: *kfs.drivers.cmos.CMOS) void {
    while (updateInProgress()) {}
    self.curr_time[0] = readByte(0x00); // seconds
    self.curr_time[1] = readByte(0x02); // minutes
    self.curr_time[2] = readByte(0x04); // hours
    self.curr_time[3] = readByte(0x07); // day
    self.curr_time[4] = readByte(0x08); // month
    self.curr_time[5] = readByte(0x09); // year
    const status = readByte(0x0B);

    if ((status & 0x04) == 0) {
        self.curr_time[0] = (self.curr_time[0] & 0x0F) + ((self.curr_time[0] / 16) * 10);
        self.curr_time[1] = (self.curr_time[1] & 0x0F) + ((self.curr_time[1] / 16) * 10);
        self.curr_time[2] = ((self.curr_time[2] & 0x0F) + (((self.curr_time[2] & 0x70) / 16) * 10) ) | (self.curr_time[2] & 0x80);
        self.curr_time[3] = (self.curr_time[3] & 0x0F) + ((self.curr_time[3] / 16) * 10);
        self.curr_time[4] = (self.curr_time[4] & 0x0F) + ((self.curr_time[4] / 16) * 10);
        self.curr_time[5] = (self.curr_time[5] & 0x0F) + ((self.curr_time[5] / 16) * 10);
    }

    // Convert 12 hour clock to 24 hour clock if necessary
    if ((status & 0x02 == 0) and (self.curr_time[2] & 0x80 != 0)) {
        self.curr_time[2] = ((self.curr_time[2] & 0x7F) + 12) % 24;
    }
}

fn binToBCD(bin_val: u8) u8 {
    return (bin_val / 10 * 16) + (bin_val % 10);
}

fn setTime(self: *kfs.drivers.cmos.CMOS, timestamp: u64) void {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs =  timestamp };

    const day_secs = epoch_secs.getDaySeconds();
    const epoch_day = epoch_secs.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    
    const sec = day_secs.getSecondsIntoMinute();
    const mins = day_secs.getMinutesIntoHour();
    const hours = day_secs.getHoursIntoDay();
    const day = month_day.day_index + 1;
    const month = month_day.month.numeric();
    var year = year_day.year;
    var century: u8 = 0;
    if (year >= 2000) {
        year -= 2000;
        century = 20;
    } else {
        year -= 1900;
        century = 19;
    }

    var bin_mode: bool = false;

    var cmos_hours: u8 = hours;

    while (updateInProgress()) {}
    const status = readByte(0x0B);
    if (status & 0x02 == 0) {
        if (hours == 0)
            cmos_hours = 24;
        if (cmos_hours > 12) {
            cmos_hours -= 12;
            cmos_hours |= 0x80;
        }
    }
    if (status & 0x04 != 0)
        bin_mode = true;

    if (self.curr_time[5] != year) {
        writeByte(0x09, if (bin_mode) @intCast(year) else binToBCD(@intCast(year)));
        self.curr_time[5] = @intCast(year);
    }
    if (self.curr_time[4] != month) {
        writeByte(0x08, if (bin_mode) month else binToBCD(month));
        self.curr_time[4] = month;
    }
    if (self.curr_time[3] != day) {
        writeByte(0x07, if (bin_mode) day else binToBCD(day));
        self.curr_time[3] = day;
    }
    if (self.curr_time[2] != hours) {
        writeByte(0x04, if (bin_mode) cmos_hours else binToBCD(cmos_hours));
        self.curr_time[2] = hours;
    }
    if (self.curr_time[1] != mins) {
        writeByte(0x02, if (bin_mode) mins else binToBCD(mins));
        self.curr_time[1] = mins;
    }
    if (self.curr_time[0] != sec) {
        writeByte(0x00, if (bin_mode) sec else binToBCD(sec));
        self.curr_time[0] = sec;
    }
}

pub fn toUnixSeconds(self: *kfs.drivers.cmos.CMOS) u64 {
    const sec  = @as(u64, self.curr_time[0]);
    const min  = @as(u64, self.curr_time[1]);
    const hour = @as(u64, self.curr_time[2]);
    const day  = @as(u64, self.curr_time[3]);
    const mon  = @as(u64, self.curr_time[4]);
    const year   = @as(u64, self.curr_time[5]) + 2000;

    var days: u64 = 0;
    var y: u64 = 1970;
    while (y < year) : (y += 1) {
        days += if (isLeap(@intCast(y))) 366 else 365;
    }
    days += daysBeforeMonth(@intCast(year), @intCast(mon));
    days += day - 1;

    return (((days * 24 + hour) * 60 + min) * 60) + sec;
}

fn isLeap(y: u32) bool {
    return (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0));
}

fn daysBeforeMonth(y: u32, m: u32) u32 {
    const days = [_]u32{ 0,31,59,90,120,151,181,212,243,273,304,334 };
    var d = days[m - 1];
    if (m > 2 and isLeap(y))
        d += 1;
    return d;
}

fn incSec(self: *kfs.drivers.cmos.CMOS) void {
    self.curr_time[0] += 1;
    if (self.curr_time[0] >= 60) {
        self.curr_time[0] = 0;
        self.curr_time[1] += 1;
        if (self.curr_time[1] >= 60) {
            self.curr_time[1] = 0;
            self.curr_time[2] += 1;
            if (self.curr_time[2] >= 24) {
                self.curr_time[2] = 0;
                self.updateTime(self);
            }
        }
    }
}

var cmos: kfs.drivers.cmos.CMOS = undefined;

export fn _init() linksection(".init") callconv(.c) u32 {
    cmos = initCMOS();
    api.setCMOS(&cmos);
    return 0;
}

export fn _exit() linksection(".exit") callconv(.c) void {
    api.restoreCMOS();
}
