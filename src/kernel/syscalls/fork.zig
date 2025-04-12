const krn = @import("../main.zig");
const doFork = @import("../sched/process.zig").doFork;
const arch = @import("arch");

pub fn fork(state: *arch.Regs) i32 {
    return doFork(state);
}
