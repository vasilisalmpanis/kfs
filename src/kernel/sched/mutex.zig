const atomic = @import("std").atomic;
const logger = @import("../main.zig");
const tsk = @import("./task.zig");

pub const Mutex = struct {
    locked: atomic.Value(bool) = atomic.Value(bool).init(false),
    
    pub fn init() Mutex {
        return Mutex{};
    }

    pub fn lock(self: *Mutex) void {
        while (self.locked.swap(true, .acquire)) {
            // atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Mutex) void {
        self.locked.store(false, .release);
    }
};
