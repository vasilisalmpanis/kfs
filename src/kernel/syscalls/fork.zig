const krn = @import("../main.zig");
const doFork = @import("../sched/process.zig").doFork;
const arch = @import("arch");
const errors = @import("error-codes.zig");

pub fn fork() !u32 {
    return try doFork();
}
