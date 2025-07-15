const io = @import("arch").io;
const dbg = @import("debug");
const krn = @import("kernel");

pub const CMOS = struct {
    curr_time: [7]u8 = .{0} ** 7,
    pub const CMOS_ADDRESS = 0x70;
    pub const CMOS_DATA = 0x71;

    pub fn init() CMOS {
        var _cmos= CMOS{
            .curr_time = .{0} ** 7,
        };
        _cmos.updateTime();
        return _cmos;
    }

    pub fn readByte(reg: u8) u8 {
        io.outb(CMOS_ADDRESS, reg);
        return io.inb(CMOS_DATA);
    }

    pub fn writeByte(reg: u8, value: u8) void {
        io.outb(CMOS_ADDRESS, reg);
        io.outb(CMOS_DATA, value);
    }

    fn updateInProgress() bool {
        writeByte(CMOS_ADDRESS, 0x0A);
        return (readByte(0x0B) & 0x80) != 0;
    }

    pub fn updateTime(self: *CMOS) void {
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

    pub fn getTime(self: *CMOS) [6]u8 {
        return self.curr_time;
    }

    pub fn incSec(self: *CMOS) void {
        self.curr_time[0] += 1;
        if (self.curr_time[0] >= 60) {
            self.curr_time[0] = 0;
            self.curr_time[1] += 1;
            if (self.curr_time[1] >= 60) {
                self.curr_time[1] = 0;
                self.curr_time[2] += 1;
                if (self.curr_time[2] >= 24) {
                    self.curr_time[2] = 0;
                    self.updateTime();
                }
            }
        }
    }

    pub fn printTime(self: *CMOS) void {
        self.updateTime();
        const time = self.curr_time;
        var year: u16 = (time[5] & 0x7F);
        year += 2000;
        const month = time[4];
        const day = time[3];
        const hours = time[2];
        const minutes = time[1];
        const seconds = time[0];
        dbg.printf("Current Time: {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}\n", .{
            year,
            month,
            day,
            hours,
            minutes,
            seconds
        });
    }
};

pub fn init() void {
    krn.cmos = CMOS.init();
}
