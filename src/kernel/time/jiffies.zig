pub var jiffies: u32 = 0;

pub fn timer_handler() void {
    jiffies += 1;
}
