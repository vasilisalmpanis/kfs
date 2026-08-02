pub const acpi = @import("../system/acpi.zig");
pub const apic = @import("apic.zig");
pub const ioapic = @import("ioapic.zig");
const krn = @import("kernel");
const arch = @import("../main.zig");
const pit = @import("drivers").pit;
const percpu = @import("./percpu.zig");
pub const PerCpu = percpu.PerCpu;

pub var boot_cpu_apicid: u32 = 0xFFFFFFFF;
pub var cpu_count: usize = 0;
pub var smp_enabled: bool = false;

pub var cpus_online: u32 = 0;

const APIC_ID: u32 = 0x20 / 4;

const APIC_TPR: u32 = 0x80 / 4;
const APIC_EOI: u32 = 0xB0 / 4;

const SPURIOUS_IVR: u32 = 0xF0 / 4;
const ERROR_STATUS_REGISTER: u32 = 0x280 / 4;
// Interrupt Command Register (low/high dwords). Note: this is the ICR at
// 0x300/0x310, not the In-Service Register (0x100).
const ICR_LOW: u32 = 0x300 / 4;
const ICR_HIGH: u32 = 0x310 / 4;
// APIC LVT Timer
const APIC_LVT_TMR: u32     = 0x320 / 4;
const APIC_LVT_PERF: u32 	= 0x340 / 4;
const APIC_LVT_LINT0: u32 	= 0x350 / 4;
const APIC_LVT_LINT1: u32 	= 0x360 / 4;
const APIC_LVT_ERR: u32 	= 0x370 / 4;
const APIC_TMRINITCNT: u32 	= 0x380 / 4;
const APIC_TMRCURRCNT: u32 	= 0x390 / 4;
const APIC_TMRDIV: u32          = 0x3E0 / 4;
const APIC_LDR: u32             = 0xD0 / 4;
const APIC_DFR: u32             = 0xE0 / 4;

const APIC_TIMER_PERIODIC: u32 = 0x20000;

const DELIVERY_STATUS: u32 = 1 << 12; // ICR low bit 12: send pending

const INIT: u32 = 0x500; // delivery mode 101 << 8
const SIPI: u32 = 0x600; // delivery mode 110 << 8
const LEVEL_ASSERT: u32 = 1 << 14; // bit 14: level (1 = assert, 0 = de-assert)
const TRIGGER_LEVEL: u32 = 1 << 15; // bit 15: trigger mode (1 = level)

pub export var ap_stack: u32 = 0;

var apic_regs: [*] volatile u32 = undefined;

fn enable_apic() void {
    apic_regs[SPURIOUS_IVR] = apic_regs[SPURIOUS_IVR] | 0x1FF;
    apic_regs[APIC_DFR] = 0xFFFFFFFF;
    const logical_id: u32 = @as(u32, 1) << @intCast(cpuID() & 0x7);
    apic_regs[APIC_LDR] = logical_id << 24;
    apic_regs[APIC_TPR] = 0x0;
}

pub fn waitCPU() void {
    while ((apic_regs[ICR_LOW] & DELIVERY_STATUS) != 0) {}
}

pub fn apicEOI() void {
    apic_regs[APIC_EOI] = 0;
}

pub fn cpuID() u32 {
    const apic_id: u32 = apic_regs[APIC_ID];
    return (apic_id >> 24) & 0xFF;
}

extern var smp_trampoline_start: u32;
extern var smp_trampoline_end: u32;

pub const TRAMPOLINE_ADDR: u32 = 0x8000;

fn setup_trampoline() void {
    const dest: [*]u8 = @ptrFromInt(TRAMPOLINE_ADDR);
    const trampoline: [*]u8 = @ptrFromInt(@intFromPtr(&smp_trampoline_start));
    const size: u32 = @intFromPtr(&smp_trampoline_end) - @intFromPtr(&smp_trampoline_start);
    @memcpy(dest[0..size], trampoline[0..size]);
}

fn setupTimer() void {
    enable_apic();
    apic_regs[APIC_LVT_TMR] = 0x20 | APIC_TIMER_PERIODIC;
    apic_regs[APIC_TMRDIV] = 0x3;
    apic_regs[APIC_TMRINITCNT] = 100;
}

pub export fn apMain() noreturn {
    arch.gdt.gdtInit(arch.gdt.gdt_ptr.ptrFromBase(percpu.percpu_curr_addr),
        arch.gdt.tss.ptrFromBase(percpu.percpu_curr_addr),
        percpu.percpu_curr_addr,
        percpu.percpu_size,
        arch.gdt.gdt_entries.ptrFromBase(percpu.percpu_curr_addr),
    );
    _ = @atomicRmw(u32, &cpus_online, .Add, 1, .seq_cst);
    arch.idt.idtLoad();

    krn.logger.INFO("Hello from cpu\n", .{});

    setupTimer();

    // arch.cpu.enableInterrupts();
    while (true) {}
}

pub fn startCore(proc_apic: *align(1) apic.ProcessorLocalAPIC) void {
    const dest_id = @as(u32, proc_apic.apic_id);
    const stack_base = krn.kthread.kthreadStackAlloc(krn.kthread.STACK_PAGES);
    if (stack_base == 0) {
        krn.logger.WARN("Could not allocate stack for CPU {d}\n",
            .{proc_apic.apic_id}
        );
        return;
    }
    // Stack grows down: point esp at the top of the allocation.
    ap_stack = stack_base + krn.kthread.STACK_SIZE;

    const before = @atomicLoad(u32, &cpus_online, .seq_cst);
    var accept_status: u32 = 0;
    // INIT assert (level-triggered, asserted).
    apic_regs[ICR_HIGH] = dest_id << 24;
    apic_regs[ICR_LOW] = INIT | LEVEL_ASSERT | TRIGGER_LEVEL;
    waitCPU();
    // INIT de-assert (level-triggered, de-asserted).
    apic_regs[ICR_HIGH] = dest_id << 24;
    apic_regs[ICR_LOW] = INIT | TRIGGER_LEVEL;
    waitCPU();
    pit.mdelay(10); // 10ms after INIT per Intel MP spec
    // SIPI x2
    for (0..1) |_| {
        apic_regs[ERROR_STATUS_REGISTER] = 0;
        apic_regs[ICR_HIGH] = dest_id << 24;
        apic_regs[ICR_LOW] = SIPI | (TRAMPOLINE_ADDR >> 12);
        waitCPU();
        pit.udelay(200);
        accept_status = apic_regs[ERROR_STATUS_REGISTER] & 0xEF;
        if (accept_status != 0)
            break;
    }
    if (accept_status != 0) {
        krn.logger.WARN(
            "CPU {d} accept status is not 0: {d}\n",
            .{proc_apic.apic_id, accept_status}
        );
    } else {
        // Busy-wait up to ~200ms for the AP to signal it's online.
        // Uses udelay (not task.sleep) because interrupts are
        // disabled during bringup, so the scheduler never runs and
        // a sleep would hang forever.
        var timeout: u32 = 2000; // 2000 * 100us = 200ms
        while (@atomicLoad(u32, &cpus_online, .seq_cst) == before and timeout > 0) {
            pit.udelay(100);
            timeout -= 1;
        }
        if (timeout == 0) {
            krn.logger.WARN("CPU {d} did not come online\n", .{proc_apic.apic_id});
        } else {
            krn.logger.INFO("CPU {d} online\n", .{proc_apic.apic_id});
            percpu.percpu_curr_addr += percpu.percpu_size_aligned;
        }
    }
}

pub fn countCPUs(madt: *apic.MADT) usize {
    var cpus: usize = 0;
    var madt_entry: ?*apic.MADTEntry = null;
    while (madt.getNextEntry(madt_entry)) |entry| {
        if (entry.type == apic.MADTTYP_PROC_LAPIC)
            cpus += 1;
        madt_entry = entry;
    }
    return cpus;
}

pub fn init() void {
    const rsdt = acpi.rsdt orelse
        return ;
    const apic_header = rsdt.getEntery("APIC") orelse
        return ;
    krn.logger.INFO("APIC HEADER: {any}", .{apic_header});

    const madt: *apic.MADT = @ptrCast(apic_header);
    cpu_count = countCPUs(madt);

    const apic_base: u32 = madt.local_address;
    const apic_page = krn.mm.mapPhys(
        apic_base,
        1,
        .{ .present = true, .writable = true, .cache_disable = true}
    ) catch
        return;
    apic_regs = @ptrFromInt(apic_page);

    boot_cpu_apicid = cpuID();
    krn.logger.INFO("boot_cpu_apicid: {d}", .{boot_cpu_apicid});

    // map first 4 megabytes
    arch.vmm.initial_page_dir[0] = 0x00000083;
    setup_trampoline();
    setupTimer();

    percpu.initPerCPUMemory() catch |e| {
        krn.logger.INFO("SMP: Cannot bring up secondary cores {any}", .{e});
        return;
    };

    var madt_entry: ?*apic.MADTEntry = null;
    while (madt.getNextEntry(madt_entry)) |entry| {
        switch (entry.type) {
            apic.MADTTYP_PROC_LAPIC => {
                const proc_apic: *align(1) apic.ProcessorLocalAPIC = @ptrCast(entry);
                if ((proc_apic.flags & 0b11) == 0) {
                    krn.logger.INFO(
                        "CPU {d} not usable, skipping\n",
                        .{proc_apic.apic_id}
                    );
                } else if (proc_apic.apic_id != boot_cpu_apicid) {
                    startCore(proc_apic);
                } else {
                    _ = @atomicRmw(u32, &cpus_online, .Add, 1, .seq_cst);
                }
            },
            apic.MADTTYP_IOAPIC => {
                const ioapic_entry: *align(1) apic.IOAPIC = @ptrCast(entry);
                krn.logger.INFO("IOAPIC entry {any}", .{ioapic_entry});
                ioapic.init(ioapic_entry) catch {};
            },
            apic.MADTTYP_IOAPIC_ISR => {
                const ioapic_gsi_override: *align(1) apic.IOAPICInterruptSourceOverride = @ptrCast(entry);
                ioapic.registerOverride(ioapic_gsi_override);
                krn.logger.INFO("IOAPIC source override {any}", .{ioapic_gsi_override});
            },
            else => {}
        }
        madt_entry = entry;
    }
    while (@atomicLoad(u32, &cpus_online, .seq_cst) == 1) {}
    if (ioapic.controller) |*cntr|
        cntr.maskAll();
    smp_enabled = true;
    krn.logger.INFO("Number of online cpus {d}\n", .{@atomicLoad(u32, &cpus_online, .seq_cst)});
}
