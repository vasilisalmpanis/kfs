const drivers = @import("drivers");
const krn = @import("../main.zig");
const vdso = @import("../vdso.zig");
pub var jiffies: u32 = 0;
pub var cpu_user_ticks: u64 = 0;
pub var cpu_system_ticks: u64 = 0;
pub var cpu_idle_ticks: u64 = 0;

pub const CpuTicks = struct {
    user: u64,
    system: u64,
    idle: u64,
};

var fb_counter: u8 = 0;
var hz_counter: u32 = 0;

pub fn timerHandler() void {
    jiffies += 1;
    fb_counter += 1;
    hz_counter += 1;

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

    if (hz_counter == drivers.pit.HZ) {
        hz_counter = 0;
        // Every second
        krn.cmos.incSec(krn.cmos);
        vdso.updateTime(1, 0);
    } else {
        vdso.updateTime(0, @intCast(drivers.pit.ns_in_one_tick));
    }
    if (fb_counter == 30) {
        fb_counter = 0;
        if (krn.screen.framebuffer.has_dirty)
            drivers.framebuffer.render_queue.wakeUpOne();
    }
}

pub fn getSecondsFromStart() u32 {
    return (jiffies / drivers.pit.HZ);
}

pub fn getTimeFromStart() krn.time.kernel_timespec {
    const seconds: i32 = @intCast(jiffies / drivers.pit.HZ);
    const sub_jiffies: u32 = jiffies % drivers.pit.HZ;
    const nanoseconds: i32 = @intCast(sub_jiffies * (1_000_000_000 / drivers.pit.HZ));
    return krn.time.kernel_timespec{
        .tv_sec = seconds,
        .tv_nsec = nanoseconds,
    };
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
