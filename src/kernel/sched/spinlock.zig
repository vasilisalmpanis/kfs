const atomic = @import("std").atomic;
const tsk = @import("./task.zig");
const std = @import("std");
const arch = @import("arch");
const sched = @import("./scheduler.zig");
const dbg = @import("debug");

pub const Spinlock = struct {
    locked: atomic.Value(bool) = atomic.Value(bool).init(false),

    pub fn init() Spinlock {
        return Spinlock{};
    }

    // Takes the lock.
    // Can be used in atomic context.
    pub fn lock(self: *Spinlock) void {
        sched.preemtionDisable();
        while (self.locked.swap(true, .acquire)) {
            sched.preemtionEnable();
            std.atomic.spinLoopHint();
            sched.preemtionDisable();
        }
    }

    // Releases the lock.
    // Can be used in atomic context.
    pub fn unlock(self: *Spinlock) void {
        self.locked.store(false, .release);
        sched.preemtionEnable();
    }

    // Disables interrupts before taking the lock
    // Can be take in process context.
    pub fn lock_irq_disable(self: *Spinlock) bool {
        const lock_state = arch.cpu.areIntEnabled();
        if (lock_state)
            arch.cpu.disableInterrupts();

        while (self.locked.swap(true, .acquire)) {
            // After failing to acquire the lock, remaining with
            // interrupts disabled doesn't allow the current cpu
            // to unblock other waits e.g when sending IPIs and
            // requiring ack. Reenable interrupts before noop and
            // disable them again when trying to swap to allow
            // a context switch to happen.
            if (lock_state)
                arch.cpu.enableInterrupts();
            std.atomic.spinLoopHint();
            if (lock_state)
                arch.cpu.disableInterrupts();
        }
        return lock_state;
    }

    // Enables interrupts after releasing the lock
    // Can be take in process context.
    pub fn unlock_irq_enable(self: *Spinlock, lock_state: bool) void {
        self.locked.store(false, .release);
        if (lock_state)
            arch.cpu.enableInterrupts();
    }
};
