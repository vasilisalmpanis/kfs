const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const signals = @import("../sched/signals.zig");

pub fn kill(_: *arch.Regs, pid: u32, sig: u32) i32 {
    if (tsk.initial_task.findByPid(pid)) |task| {
        defer task.refcount.unref();
        const signal: signals.Signal = @enumFromInt(sig);
        task.sighand.setSignal(signal);
        if (task.state != .ZOMBIE and task.state != .STOPPED)
            task.state = .RUNNING;
        return 0;
    }
    return -errors.EPERM;
}
