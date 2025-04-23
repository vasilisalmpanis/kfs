const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const sched = @import("../sched/scheduler.zig");

pub fn exit(_: *arch.Regs, error_code: i32) i32 {
    tsk.current.result = error_code;
    tsk.current.state = .ZOMBIE;
    if (tsk.current.tree.parent) |p| {
        _ = p;
        // const parent = p.entry(tsk.Task, "tree");
        // parent.sigaction.setSignal(.SIGCHLD);
        // Lets comment this in when signals are ready.
    }
    sched.reschedule();
    return 0;
}
