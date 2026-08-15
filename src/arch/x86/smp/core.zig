const arch = @import("../main.zig");
const smp = @import("main.zig");
const krn = @import("kernel");
const pit = @import("drivers").pit;

// Interrupt Command Register (low/high dwords). Note: this is the ICR at
// 0x300/0x310, not the In-Service Register (0x100).
const APIC_EOI_REGISTER: u32        = 0xB0 / 4;
const ERROR_STATUS_REGISTER: u32    = 0x280 / 4;
const ICR_LOW_REGISTER: u32         = 0x300 / 4;
const ICR_HIGH_REGISTER: u32        = 0x310 / 4;

const INIT: u32 = 0x500; // delivery mode 101 << 8
const SIPI: u32 = 0x600; // delivery mode 110 << 8
const LEVEL_ASSERT: u32 = 1 << 14; // bit 14: level (1 = assert, 0 = de-assert)
const TRIGGER_LEVEL: u32 = 1 << 15; // bit 15: trigger mode (1 = level)
const DELIVERY_STATUS: u32 = 1 << 12; // ICR low bit 12: send pending

pub fn wait() void {
    while ((smp.apic_regs[ICR_LOW_REGISTER] & DELIVERY_STATUS) != 0) {}
}

pub fn start(proc_apic: *align(1) smp.apic.ProcessorLocalAPIC) void {
    const dest_id = @as(u32, proc_apic.apic_id);
    const stack_base = krn.kthread.kthreadStackAlloc(krn.kthread.STACK_PAGES);
    if (stack_base == 0) {
        krn.logger.WARN("Could not allocate stack for CPU {d}\n",
            .{proc_apic.apic_id}
        );
        return;
    }
    // Stack grows down: point esp at the top of the allocation.
    smp.ap_stack = stack_base + krn.kthread.STACK_SIZE;

    const before = smp.cpus_online.load(.monotonic);
    var accept_status: u32 = 0;
    // INIT assert (level-triggered, asserted).
    smp.apic_regs[ICR_HIGH_REGISTER] = dest_id << 24;
    smp.apic_regs[ICR_LOW_REGISTER] = INIT | LEVEL_ASSERT | TRIGGER_LEVEL;
    wait();
    // INIT de-assert (level-triggered, de-asserted).
    smp.apic_regs[ICR_HIGH_REGISTER] = dest_id << 24;
    smp.apic_regs[ICR_LOW_REGISTER] = INIT | TRIGGER_LEVEL;
    wait();
    pit.mdelay(10); // 10ms after INIT per Intel MP spec
    // SIPI
    for (0..1) |_| {
        smp.apic_regs[ERROR_STATUS_REGISTER] = 0;
        smp.apic_regs[ICR_HIGH_REGISTER] = dest_id << 24;
        smp.apic_regs[ICR_LOW_REGISTER] = SIPI | (smp.TRAMPOLINE_ADDR >> 12);
        wait();
        pit.udelay(200);
        accept_status = smp.apic_regs[ERROR_STATUS_REGISTER] & 0xEF;
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
        while (smp.cpus_online.load(.seq_cst) == before and timeout > 0) {
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

fn sendIPI(apic_id: u32, vector: u8) void {
    arch.cpu.disableInterrupts();
    wait();
    smp.apic_regs[ICR_HIGH_REGISTER] = @as(u32, apic_id) << 24;
    smp.apic_regs[ICR_LOW_REGISTER] = @as(u32, vector) | LEVEL_ASSERT;
    wait();
    arch.cpu.enableInterrupts();
}


fn sendEOI(_: u32) void {
    smp.apic_regs[APIC_EOI_REGISTER] = 0;
}

pub fn init() void {
    arch.cpu.operations.sendEOI = sendEOI;
    arch.cpu.operations.sendIPI = sendIPI;
    krn.irq.registerIPIHandler(
        arch.idt.TLB_INTERRUPT,
        arch.vmm.shootdownTLB
    );
}
