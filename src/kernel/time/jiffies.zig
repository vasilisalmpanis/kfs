const drivers = @import("drivers");
const krn = @import("../main.zig");
pub var jiffies: u32 = 0;

pub fn timerHandler() void {
    jiffies += 1;

    if (jiffies % drivers.pit.HZ == 0) {
        // Every second
        krn.cmos.incSec();
    }
}

pub fn getSecondsFromStart() u32 {
    return (jiffies / drivers.pit.HZ);
}

pub fn currentMs() u32 {
    if (drivers.pit.HZ < 1000) {
        return (jiffies * (1000 / drivers.pit.HZ));
    } else {
        return (jiffies / (drivers.pit.HZ / 1000));
    }
}
