const arch = @import("../main.zig");
const smp = arch.smp;
const pit = @import("drivers").pit;
// Regs
const APIC_TMRINITCNT: u32      = 0x380 / 4;
const APIC_TMRCURRCNT: u32      = 0x390 / 4;
const APIC_LVT_TMR: u32         = 0x320 / 4;
const APIC_TMRDIV: u32          = 0x3E0 / 4;
// Values
const APIC_TIMER_PERIODIC: u32  = 0x20000;
const LVT_MASKED: u32           = 0x10000;
const TMRDIV_BY_16: u32         = 0x3;
const DEFAULT_TMRINITCNT: u32   = 100_000;

var lapic_ticks_per_jiffies: u32 = 0;

pub fn calibrate() void {
    smp.enable_apic();
    smp.apic_regs[APIC_TMRDIV]     = TMRDIV_BY_16;
    smp.apic_regs[APIC_LVT_TMR]    = LVT_MASKED;
    smp.apic_regs[APIC_TMRINITCNT] = 0xFFFFFFFF;

    pit.setupPit2();
    const p_start = pit.readPit2();
    const a_start = smp.apic_regs[APIC_TMRCURRCNT];

    // ~30 ms
    while (((@as(u32, p_start) -% @as(u32, pit.readPit2())) & 0xFFFF) < 35_000) {}

    const a_end = smp.apic_regs[APIC_TMRCURRCNT];
    const p_end = pit.readPit2();

    const p_ticks: u32 = (@as(u32, p_start) -% @as(u32, p_end)) & 0xFFFF;
    const apic_elapsed: u64 = @as(u64, a_start) - @as(u64, a_end);
    const us: u64 = @as(u64, p_ticks) * 1_000_000 / pit.CLOCK_FREQ;
    if (us == 0)
        return;
    const per_sec: u64 = apic_elapsed * 1_000_000 / us;
    lapic_ticks_per_jiffies = @intCast(per_sec / pit.HZ);
    if (lapic_ticks_per_jiffies == 0)
        lapic_ticks_per_jiffies = 1;
}

pub fn setup() void {
    smp.enable_apic();
    smp.apic_regs[APIC_LVT_TMR] = arch.idt.TIMER_INTERRUPT | APIC_TIMER_PERIODIC;
    smp.apic_regs[APIC_TMRDIV] = TMRDIV_BY_16;
    smp.apic_regs[APIC_TMRINITCNT] = if (lapic_ticks_per_jiffies == 0)
        DEFAULT_TMRINITCNT
    else
        lapic_ticks_per_jiffies;
}
