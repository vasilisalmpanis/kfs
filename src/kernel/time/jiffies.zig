const drivers = @import("drivers");
const krn = @import("../main.zig");
pub var jiffies: u32 = 0;
pub var cpu_user_ticks: u64 = 0;
pub var cpu_system_ticks: u64 = 0;
pub var cpu_idle_ticks: u64 = 0;

pub const CpuTicks = struct {
    user: u64,
    system: u64,
    idle: u64,
};

pub fn timerHandler() void {
    jiffies += 1;

    const current = krn.task.current;
    if (current == &krn.task.initial_task) {
        cpu_idle_ticks += 1;
    } else if (current.regs.isRing3()) {
        cpu_user_ticks += 1;
        current.utime += 1;
    } else {
        cpu_system_ticks += 1;
        current.stime += 1;
    }

    if (jiffies % drivers.pit.HZ == 0) {
        // Every second
        krn.cmos.incSec(krn.cmos);
    }
    if (jiffies % 30 == 0 and krn.screen.framebuffer.has_dirty)
        drivers.framebuffer.render_queue.wakeUpOne();
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

pub fn getCpuTicks() CpuTicks {
    return .{
        .user = cpu_user_ticks,
        .system = cpu_system_ticks,
        .idle = cpu_idle_ticks,
    };
}
