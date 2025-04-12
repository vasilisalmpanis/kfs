const tsk = @import("../sched/task.zig");
const signal = @import("../sched/signals.zig");
const errors = @import("../main.zig").errors;
const arch = @import("arch");

pub fn kill(_: *arch.Regs, pid: u32, sig: u32) i32 {
    if (tsk.initial_task.findByPid(pid)) |task| {
        defer task.refcount.unref();
        task.sigaction.setSignal(@enumFromInt(sig));
        return 0;
    }
    return -errors.EPERM;
}
