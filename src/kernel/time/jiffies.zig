const std = @import("std");
const drivers = @import("drivers");
const krn = @import("../main.zig");
const vdso = @import("../vdso.zig");
const arch = @import("arch");

pub var jiffies: u32 = 0;
pub const cpu_user_ticks = arch.smp.PerCpu(u64, 0, opaque {});
pub const cpu_system_ticks = arch.smp.PerCpu(u64, 0, opaque {});
pub const cpu_idle_ticks = arch.smp.PerCpu(u64, 0, opaque {});

pub const CpuTicks = struct {
    user: u64,
    system: u64,
    idle: u64,
};

var fb_counter: u32 = 0;
var hz_counter: u32 = 0;

var boot_tsc: u64 = 0;
var cycles_per_tick: u64 = 0;

pub fn initTimebase() void {
    cycles_per_tick = drivers.pit.tsc_per_ms * 1000 / drivers.pit.HZ;
    boot_tsc = arch.cpu.rdtsc();
}

pub fn accountTick(regs: *arch.Regs) void {
    const current = krn.task.current();
    if (current == krn.task.initial_task.ptr()) {
        cpu_idle_ticks.ptr().* += 1;
    } else if (regs.isRing3()) {
        cpu_user_ticks.ptr().* += 1;
        current.utime += 1;
    } else {
        cpu_system_ticks.ptr().* += 1;
        current.stime += 1;
    }
}

pub fn timerHandler() void {
    if (arch.smp.logical_id.get() != 0)
        return ;

    if (cycles_per_tick == 0) {
        jiffies += 1;
        return ;
    }

    const now: u32 = @truncate((arch.cpu.rdtsc() -% boot_tsc) / cycles_per_tick);
    const prev = jiffies;
    jiffies = now;
    const elapsed: u32 = now -% prev;
    if (elapsed == 0)
        return ;

    hz_counter += elapsed;
    if (hz_counter >= drivers.pit.HZ) {
        const seconds = hz_counter / drivers.pit.HZ;
        hz_counter %= drivers.pit.HZ;
        if (krn.cmos_ready.*) {
            for (0..seconds) |_|
                krn.cmos.incSec(krn.cmos);
        }
        vdso.updateTime(@intCast(seconds), 0);
    } else {
        vdso.updateTime(0, @intCast(elapsed * drivers.pit.ns_in_one_tick));
    }

    fb_counter += elapsed;
    if (fb_counter >= 30) {
        fb_counter = 0;
        if (krn.screen.framebuffer.has_dirty)
            drivers.framebuffer.render_queue.wakeUpOne();
    }
}

pub fn getSecondsFromStart() u32 {
    return (jiffies / drivers.pit.HZ);
}

pub fn getTimeFromStart() krn.time.kernel_timespec {
    const _jiffies = jiffies;
    const seconds: i32 = @intCast(_jiffies / drivers.pit.HZ);
    const sub_jiffies: u32 = _jiffies % drivers.pit.HZ;
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
    var _cpu_user_ticks: u64 = 0;
    var _cpu_system_ticks: u64 = 0;
    var _cpu_idle_ticks: u64 = 0;
    for (0..arch.smp.cpu_count) |logical_id| {
        _cpu_user_ticks += cpu_user_ticks.ptrOn(logical_id).*;
        _cpu_idle_ticks += cpu_idle_ticks.ptrOn(logical_id).*;
        _cpu_system_ticks += cpu_system_ticks.ptrOn(logical_id).*;
    }
    return .{
        .user = _cpu_user_ticks,
        .system = _cpu_system_ticks,
        .idle = _cpu_idle_ticks,
    };
}
