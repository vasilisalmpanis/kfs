const tsk = @import("../sched/task.zig");
const arch = @import("arch");
const sched = @import("../sched/scheduler.zig");
const signals = @import("../sched/signals.zig");
const kernel = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;

pub fn doExit(error_code: i32) !u32 {
    if (tsk.current == &tsk.initial_task)
        return errors.EINVAL;

    tsk.current.result = error_code;

    const lock_state = kernel.task.tasks_lock.lock_irq_disable();
    if (tsk.current.tree.parent) |p| {
        const parent = p.entry(tsk.Task, "tree");
        const act = parent.sighand.actions.get(.SIGCHLD);

        tsk.current.state = .ZOMBIE;
        if (act.flags & signals.SA_NOCLDWAIT != 0)
            tsk.current.finish(true);

        tsk.current.wakeupParent(true);
        if (act.handler.handler != signals.sigIGN)
            parent.sighand.setSignal(.SIGCHLD);
    }
    if (tsk.current.mm) |_mm| {
        _mm.delete();
    }
    tsk.current.files.deinit();
    tsk.current.fs.deinit();
    kernel.task.tasks_lock.unlock_irq_enable(lock_state);
    sched.reschedule();
    return 0;
}

pub fn exit(error_code: i32) !u32 {
    return try doExit((error_code & 0xff) << 8);
}
