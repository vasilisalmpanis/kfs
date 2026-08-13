pub const acpi = @import("../system/acpi.zig");
pub const apic = @import("apic.zig");
pub const ioapic = @import("ioapic.zig");
const krn = @import("kernel");
const arch = @import("../main.zig");
const pit = @import("drivers").pit;
const percpu = @import("./percpu.zig");
const std = @import("std");
pub const PerCpu = percpu.PerCpu;

pub var boot_cpu_apicid: u32 = 0xFFFFFFFF;
pub var cpu_count: usize = 1;
pub var smp_enabled: bool = false;

pub const logical_id = PerCpu(u32, 0xFFFFFFFF, opaque{});
pub const physical_id = PerCpu(u32, 0xFFFFFFFF, opaque{});

pub var cpu_logical_ids: std.AutoHashMap(u32, u32) = undefined;
pub var cpus_online: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

var lapic_ticks_per_jiffies: u32 = 0;

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
const LVT_MASKED: u32 = 0x10000;
const TMRDIV_BY_16: u32 = 0x3;
const DEFAULT_TMRINITCNT: u32 = 100_000;

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
    const curr_physical_id: u32 = @as(u32, 1) << @intCast(cpuID() & 0x7);
    apic_regs[APIC_LDR] = curr_physical_id << 24;
    apic_regs[APIC_TPR] = 0x0;
}

pub fn sendIPIMaskButSelf(
    set: std.bit_set.IntegerBitSet(32),
    vector: u8
) void {
    var it = set.iterator(.{ .direction = .forward, .kind = .set });
    const current_id = logical_id.get();
    while (it.next()) |_logical_id| {
        if (_logical_id ==  current_id)
            continue;
        sendIPI(physical_id.ptrOn(_logical_id).*, vector);
    }
}

pub fn sendIPIAllButSelf(vector: u8) void {
    for (0..cpu_count) |_logical_id| {
        sendIPI(physical_id.ptrOn(_logical_id).*, vector);
    }
}

pub fn sendIPI(apic_id: u32, vector: u8) void {
    waitCPU();
    apic_regs[ICR_HIGH] = @as(u32, apic_id) << 24;
    apic_regs[ICR_LOW] = @as(u32, vector) | LEVEL_ASSERT;
    waitCPU();
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

fn calibrateApicTimer() void {
    enable_apic();
    apic_regs[APIC_TMRDIV]     = TMRDIV_BY_16;
    apic_regs[APIC_LVT_TMR]    = LVT_MASKED;
    apic_regs[APIC_TMRINITCNT] = 0xFFFFFFFF;

    pit.setupPit2();
    const p_start = pit.readPit2();
    const a_start = apic_regs[APIC_TMRCURRCNT];

    // ~30 ms
    while (((@as(u32, p_start) -% @as(u32, pit.readPit2())) & 0xFFFF) < 35_000) {}

    const a_end = apic_regs[APIC_TMRCURRCNT];
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

fn setupTimer() void {
    enable_apic();
    apic_regs[APIC_LVT_TMR] = arch.idt.TIMER_INTERRUPT | APIC_TIMER_PERIODIC;
    apic_regs[APIC_TMRDIV] = TMRDIV_BY_16;
    apic_regs[APIC_TMRINITCNT] = if (lapic_ticks_per_jiffies == 0)
        DEFAULT_TMRINITCNT
    else
        lapic_ticks_per_jiffies;
}

// If we reach idle that means we have no tasks to run
// we halt
// some other cpu puts a task on our list
// it tries to wake us up.
// (how ?) IPI?
// idle does schedule -> runnable task runs

fn idle() noreturn {
    while (true) {
        if (!arch.cpu.areIntEnabled()) {
            arch.cpu.cpuRelax();
        }
        arch.cpu.halt();
        krn.sched.schedule();
    }
}

pub export fn apMain() noreturn {
    const stack_top: u32 = ap_stack;
    const stack_bottom: usize = @intCast(stack_top - krn.kthread.STACK_SIZE);

    const curr_phys_id: u32 = cpuID();
    const curr_logical_id: u32 = cpu_logical_ids.get(curr_phys_id) orelse {
        @panic("AP: Bug, physical ID doesn't exist in hashmap");
    };
    _ = cpus_online.fetchAdd(1, .monotonic);
    const percpu_addr: u32 = percpu.cpuBase(curr_logical_id);

    arch.gdt.gdtInit(
        arch.gdt.gdt_ptr.ptrFromBase(percpu_addr),
        arch.gdt.tss.ptrFromBase(percpu_addr),
        percpu_addr,
        percpu.percpu_size - 1,
        arch.gdt.gdt_entries.ptrFromBase(percpu_addr),
    );
    // Percpu variables can be used

    logical_id.set(curr_logical_id);
    physical_id.set(curr_phys_id);

    arch.gdt.tss.ptr().esp0 = stack_top; // TODO: Remove this and use a hashmap
    krn.task.initCpuLocal(
        stack_top,
        stack_bottom,
    );

    arch.idt.idtLoad();

    krn.logger.INFO(
        \\
        \\- --------------
        \\AP:           {d}
        \\Logical ID:   {d}
        \\Stack Top:    {x}
        \\Percpu Base:  {x}
        \\---------------
        \\
        ,.{
            physical_id.get(),
            logical_id.get(),
            krn.task.stack_top.get(),
            percpu.cpuBase(logical_id.get()),
        }
    );

    setupTimer();

    arch.fpu.initFPU();
    arch.fpu.setTaskSwitched();
    arch.cpu.enableInterrupts();
    idle();
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

    const before = cpus_online.load(.monotonic);
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
    // SIPI
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
        while (cpus_online.load(.seq_cst) == before and timeout > 0) {
            pit.udelay(100);
            timeout -= 1;
        }
        if (timeout == 0) {
            krn.logger.WARN("CPU {d} did not come online\n", .{proc_apic.apic_id});
        } else {
            krn.logger.INFO("CPU {d} online\n", .{proc_apic.apic_id});
        }
    }
}

fn logicalIdsSetup(madt: *apic.MADT) !void {
    cpu_logical_ids = std.AutoHashMap(u32, u32).init(
        krn.mm.kernel_allocator.allocator()
    );
    cpu_logical_ids.put(boot_cpu_apicid, 0) catch {
        return krn.errors.PosixError.ENOMEM;
    };
    var current_id: u32 = 1;
    var madt_entry: ?*apic.MADTEntry = null;
    while (madt.getNextEntry(madt_entry)) |entry| {
        if (entry.type == apic.MADTTYP_PROC_LAPIC) {
            const proc_apic: *align(1) apic.ProcessorLocalAPIC = @ptrCast(entry);
            if (proc_apic.apic_id == boot_cpu_apicid) {

            } else if ((proc_apic.flags & 0b11) != 0) {
                try cpu_logical_ids.put(proc_apic.apic_id, current_id);
                current_id += 1;
            }
        }
        madt_entry = entry;
    }
}

pub fn countCPUs(madt: *apic.MADT) usize {
    var cpus: usize = 0;
    var madt_entry: ?*apic.MADTEntry = null;
    while (madt.getNextEntry(madt_entry)) |entry| {
        if (entry.type == apic.MADTTYP_PROC_LAPIC) {
            const proc_apic: *align(1) apic.ProcessorLocalAPIC = @ptrCast(entry);
            if ((proc_apic.flags & 0b11) != 0)
                cpus += 1;
        }
        madt_entry = entry;
    }
    return cpus;
}

pub export fn shootdownTLB() void {
    arch.vmm.switchToVAS(arch.vmm.getCR3());
}

pub fn init() void {
    logical_id.set(0);
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
    ) catch {
        cpu_count = 1;
        return;
    };
    apic_regs = @ptrFromInt(apic_page);
    calibrateApicTimer();
    setupTimer();

    boot_cpu_apicid = cpuID();
    krn.logger.INFO("boot_cpu_apicid: {d}", .{boot_cpu_apicid});

    logicalIdsSetup(madt) catch |e| {
        krn.logger.WARN("SMP: failure to create logical cpu ids map {any}", .{e});
        cpu_count = 1;
        return;
    };


    // map first 4 megabytes
    arch.vmm.initial_page_dir[0] = 0x00000083;
    setup_trampoline();

    percpu.initPerCPUMemory() catch |e| {
        krn.logger.INFO("SMP: Cannot bring up secondary cores {any}", .{e});
        cpu_count = 1;
        return;
    };

    physical_id.set(boot_cpu_apicid);

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
                    _ = cpus_online.fetchAdd(1, .seq_cst);
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
    while (cpu_count > 1 and cpus_online.load(.seq_cst) == 1) {}
    if (ioapic.controller) |*cntr|
        cntr.maskAll();
    smp_enabled = true;
    krn.logger.INFO("Number of online cpus {d}\n", .{cpus_online.load(.seq_cst)});
    cpu_logical_ids.deinit();

    krn.irq.registerIPIHandler(arch.idt.TLB_INTERRUPT, shootdownTLB);
}
