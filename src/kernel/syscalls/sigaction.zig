const tsk = @import("../sched/task.zig");
const signal = @import("../sched/signals.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const krn = @import("../main.zig");

pub fn sigaction(_: *arch.Regs, sig: u32, act: ?*signal.Sigaction, oact: ?*signal.Sigaction) i32 {
    krn.logger.INFO("sigaction {d} {any} {any}", .{sig, act, oact});
    tsk.current.sighand.actions.set(@enumFromInt(sig), act.?.*);
    return 0;
}
