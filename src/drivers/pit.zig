const io = @import("arch").io;
const krn = @import("kernel");

pub const PIT = struct {
    clock_freq: u32 = 1193182,
    frequency: u32,

    pub fn init(frequency: u32) PIT {
        var pit = PIT{
            .frequency = frequency,
        };
        pit.set_frequency(frequency);
        return pit;
    }

    fn calculate_divider(self: *PIT, frequency: u32) u16 {
        _ = self;
        var reload_value: u32 = 0;

        if (frequency <= 18) {
            reload_value = 0x10000; // Slowest possible frequency (65536)
        } else if (frequency >= 1193181) {
            reload_value = 1; // Fastest possible frequency
        } else {
            const dividend: u32 = 3579545;
            var remainder: u32 = 0;
            reload_value = dividend / frequency;
            remainder = dividend % frequency;
            if (remainder >= (dividend / 2)) {
                reload_value += 1;
            }
            const divisor: u32 = 3;
            remainder = reload_value % divisor;
            reload_value = reload_value / divisor;
            if (remainder >= (divisor / 2)) {
                reload_value += 1;
            }
        }
        return @truncate(reload_value);
    }

    pub fn set_frequency(self: *PIT, frequency: u32) void {
        self.frequency = frequency;
        const divider = self.calculate_divider(frequency);
        io.outb(0x43, 0b00110100);
        io.outb(0x40, @truncate(divider & 0xFF));
        io.outb(0x40, @truncate(divider >> 8));
    }

    pub fn get_seconds_from_start(self: *PIT) u32 {
        return (krn.jiffies.jiffies / self.frequency);
    }
};
