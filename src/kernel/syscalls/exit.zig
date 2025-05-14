const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const sched = @import("../sched/scheduler.zig");
const signals = @import("../sched/signals.zig");

pub fn exit(error_code: i32) i32 {
    tsk.current.result = error_code;
    tsk.current.state = .ZOMBIE;
    if (tsk.current.tree.parent) |p| {
        const parent = p.entry(tsk.Task, "tree");
        const act = parent.sighand.actions.get(.SIGCHLD);
        if (act.handler.handler != signals.sigIGN and (act.flags & signals.SA_NOCLDSTOP == 0))
            parent.sighand.setSignal(.SIGCHLD);
    }
    sched.reschedule();
    return 0;
}
