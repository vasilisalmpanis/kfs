pub const acpi = @import("../system/acpi.zig");
pub const apic = @import("apic.zig");
pub const ioapic = @import("ioapic.zig");
const krn = @import("kernel");
const arch = @import("../main.zig");
const percpu = @import("./percpu.zig");
const std = @import("std");
const timer = @import("apic_timer.zig");
const core = @import("core.zig");
pub const PerCpu = percpu.PerCpu;

pub var boot_cpu_apicid: u32 = 0xFFFFFFFF;
pub var cpu_count: usize = 1;
pub var smp_enabled: bool = false;

pub const logical_id = PerCpu(u32, 0xFFFFFFFF, opaque{});
pub const physical_id = PerCpu(u32, 0xFFFFFFFF, opaque{});

pub var cpu_logical_ids: std.AutoHashMap(u32, u32) = undefined;
pub var cpus_online: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

const APIC_ID: u32 = 0x20 / 4;

const APIC_TPR: u32 = 0x80 / 4;

const SPURIOUS_IVR: u32 = 0xF0 / 4;
// APIC LVT Timer
const APIC_LVT_PERF: u32 	= 0x340 / 4;
const APIC_LVT_LINT0: u32 	= 0x350 / 4;
const APIC_LVT_LINT1: u32 	= 0x360 / 4;
const APIC_LVT_ERR: u32 	= 0x370 / 4;
const APIC_LDR: u32             = 0xD0 / 4;
const APIC_DFR: u32             = 0xE0 / 4;


pub export var ap_stack: u32 = 0;

pub var apic_regs: [*] volatile u32 = undefined;

pub fn enable_apic() void {
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
    if (arch.cpu.operations.sendIPI) |_sendIPI| {
        var it = set.iterator(.{ .direction = .forward, .kind = .set });
        const current_id = logical_id.get();
        while (it.next()) |_logical_id| {
            if (_logical_id ==  current_id)
                continue;
            // krn.logger.INFO("SENDING IPI {d} current id {d}\n", .{_logical_id, current_id});
            _sendIPI(physical_id.ptrOn(_logical_id).*, vector);
        }
    }
}

pub fn sendIPIAllButSelf(vector: u8) void {
    if (arch.cpu.operations.sendIPI) |_sendIPI| {
        const current_id = logical_id.get();
        for (0..cpu_count) |_logical_id| {
            if (_logical_id == current_id)
                continue;
            _sendIPI(physical_id.ptrOn(_logical_id).*, vector);
        }
    }
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

pub fn idle() noreturn {
    while (true) {
        if (!arch.cpu.areIntEnabled()) {
            arch.cpu.cpuRelax();
        }
        arch.cpu.halt();
        krn.sched.schedule();

        krn.sched.processTasks();
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

    timer.setup();

    arch.fpu.initFPU();
    arch.fpu.setTaskSwitched();
    arch.cpu.enableInterrupts();
    idle();
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

pub fn init() void {
    logical_id.set(0);
    const rsdt = acpi.rsdt orelse
        return ;
    const apic_header = rsdt.getEntry("APIC") orelse
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
    timer.calibrate();
    timer.setup();

    boot_cpu_apicid = cpuID();
    physical_id.set(boot_cpu_apicid);
    krn.logger.INFO("boot_cpu_apicid: {d}", .{boot_cpu_apicid});

    // At this point APIC has been properly initialized for BSP so
    // interrupts will work. We now mask legacy PIC and assign the
    // cpu operations to smp callbacks.
    arch.idt.PICMask();
    core.init();

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
                    core.start(proc_apic);
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
}
