const io = @import("arch").io;
const cpu = @import("arch").cpu;

pub var HZ: u32 = 1000;
pub var ns_in_one_tick: u32 = undefined;

pub const CLOCK_FREQ: u32 = 1193182;

pub var tsc_per_ms: u64 = 0;

pub const PIT = struct {
    clock_freq: u32 = CLOCK_FREQ,

    pub fn init(frequency: u32) PIT {
        var pit = PIT{};
        pit.setFrequency(frequency);
        calibrate();
        calibrateTsc();
        return pit;
    }

    fn calculateDivider(self: *PIT, frequency: u32) u16 {
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

    pub fn setFrequency(self: *PIT, _frequency: u32) void {
        var frequency = _frequency;
        if (frequency < 1000) {
            frequency = 1000;
        }
        HZ = frequency;
        ns_in_one_tick = 1_000_000_000 / frequency;
        const divider = self.calculateDivider(frequency);
        io.outb(0x43, 0b00110100);
        io.outb(0x40, @truncate(divider & 0xFF));
        io.outb(0x40, @truncate(divider >> 8));
    }
};

// ---------------------------------------------------------------------------
// Busy-wait delays
//
// Unlike krn.task.sleep(), these don't rely on the scheduler or on timer
// interrupts, so they work with interrupts disabled (e.g. during SMP bringup).
// ---------------------------------------------------------------------------

/// Loops per microsecond. Filled in by calibrate(); 1 until then so a stray
/// early call still terminates.
pub var loops_per_us: u32 = 1;

/// Tight busy-loop — burns roughly `loops` iterations.
/// Port of Linux's __delay(): decrement until the value goes negative
/// (jns = jump while sign flag clear, i.e. while >= 0).
pub inline fn __delay(loops: u32) void {
    var count: u32 = loops;
    asm volatile (
        \\1:
        \\  decl %[count]
        \\  jns 1b
        : [count] "=r" (count),
        : [in] "0" (count),
        : .{ .cc = true }
    );
}

/// Busy-wait `us` microseconds. Use for short delays (< ~1 ms); larger values
/// risk overflowing the multiply — use mdelay() for those.
pub fn udelay(us: u32) void {
    __delay(loops_per_us *% us);
}

/// Busy-wait `ms` milliseconds.
pub fn mdelay(ms: u32) void {
    var i: u32 = 0;
    while (i < ms) : (i += 1) __delay(loops_per_us *% 1000);
}

// --- calibration via PIT channel 2 (no interrupts required) ---

pub fn setupPit2() void {
    // Speaker off (bit1=0), gate on (bit0=1) so channel 2 actually counts.
    const p: u8 = (io.inb(0x61) & 0xFC) | 0x01;
    io.outb(0x61, p);
    // Channel 2, access lo/hi byte, mode 0, binary.
    io.outb(0x43, 0xB0);
    // Load 0xFFFF; in mode 0 the counter keeps decrementing past 0 (wraps),
    // so it's a free-running down-counter we can sample.
    io.outb(0x42, 0xFF);
    io.outb(0x42, 0xFF);
}

pub fn readPit2() u16 {
    io.outb(0x43, 0x80); // counter-latch, channel 2
    const lo: u16 = @as(u16, io.inb(0x42));
    const hi: u16 = @as(u16, io.inb(0x42));
    return lo | (hi << 8);
}

/// Measure how many delay-loop iterations fit in a known amount of PIT time.
/// Call once at boot, AFTER the PIT is initialized and BEFORE smp.init().
pub fn calibrate() void {
    setupPit2();
    var loops: u32 = 1 << 12;
    while (loops < (1 << 30)) : (loops <<= 1) {
        const start = readPit2();
        __delay(loops);
        const end = readPit2();
        // Channel counts down, so elapsed = start - end (mod 65536).
        const ticks: u32 = (@as(u32, start) -% @as(u32, end)) & 0xFFFF;
        // Big enough sample to be accurate, small enough to not wrap (~54 ms).
        if (ticks >= 10_000) {
            const time_us: u64 = @as(u64, ticks) * 1_000_000 / CLOCK_FREQ;
            if (time_us != 0)
                loops_per_us = @intCast(@as(u64, loops) / time_us);
            break;
        }
    }
    if (loops_per_us == 0) loops_per_us = 1;
}

pub fn calibrateTsc() void {
    setupPit2();
    const p_start = readPit2();
    const t_start = cpu.rdtsc();

    while (((@as(u32, p_start) -% @as(u32, readPit2())) & 0xFFFF) < 35_000) {}

    const t_end = cpu.rdtsc();
    const p_end = readPit2();

    const p_ticks: u64 = (@as(u32, p_start) -% @as(u32, p_end)) & 0xFFFF;
    const time_us: u64 = p_ticks * 1_000_000 / CLOCK_FREQ;
    if (time_us != 0)
        tsc_per_ms = (t_end -% t_start) * 1_000 / time_us;
    if (tsc_per_ms == 0)
        tsc_per_ms = 1;
}
