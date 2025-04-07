const krn = @import("../main.zig");
const doFork = @import("../sched/process.zig").doFork;

pub fn fork() i32 {
    return doFork();
}
