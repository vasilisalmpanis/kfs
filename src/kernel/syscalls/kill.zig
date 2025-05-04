const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");

pub fn kill(_: *arch.Regs, pid: u32, sig: u32) i32 {
    if (tsk.initial_task.findByPid(pid)) |task| {
        defer task.refcount.unref();
        task.sighand.setSignal(@enumFromInt(sig));
        return 0;
    }
    return -errors.EPERM;
}
