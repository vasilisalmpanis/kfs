const krn = @import("../main.zig");
const doFork = @import("../sched/process.zig").doFork;
const arch = @import("arch");

pub fn fork() i32 {
    return doFork();
}
