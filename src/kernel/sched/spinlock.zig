const atomic = @import("std").atomic;
const tsk = @import("./task.zig");
const std = @import("std");
const arch = @import("arch");

pub const Spinlock = struct {
    locked: atomic.Value(bool) = atomic.Value(bool).init(false),

    pub fn init() Spinlock {
        return Spinlock{};
    }

    // Takes the lock.
    // Can be used in atomic context.
    pub fn lock(self: *Spinlock) void {
        while (self.locked.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
        }
    }

    // Releases the lock.
    // Can be used in atomic context.
    pub fn unlock(self: *Spinlock) void {
        self.locked.store(false, .release);
    }

    // Disables interrupts before taking the lock
    // Can be take in process context.
    pub fn lock_irq_disable(self: *Spinlock) bool {
        const lock_state = arch.cpu.areIntEnabled();
        if (lock_state)
            arch.cpu.disableInterrupts();
        while (self.locked.swap(true, .acquire)) {
            std.atomic.spinLoopHint();
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
