const atomic = @import("std").atomic;
const tsk = @import("./task.zig");
const reschedule = @import("./scheduler.zig").reschedule;

pub const Mutex = struct {
    locked: atomic.Value(bool) = atomic.Value(bool).init(false),
    
    pub fn init() Mutex {
        return Mutex{};
    }

    pub fn lock(self: *Mutex) void {
        while (self.locked.swap(true, .acquire)) {
            reschedule();
        }
    }

    pub fn trylock(self: *Mutex) void {
        return !self.locked.swap(true, .acquire);
    }

    pub fn unlock(self: *Mutex) void {
        self.locked.store(false, .release);
        reschedule();
    }
};
