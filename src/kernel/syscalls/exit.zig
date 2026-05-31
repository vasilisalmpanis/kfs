const tsk = @import("../sched/task.zig");
const arch = @import("arch");
const sched = @import("../sched/scheduler.zig");
const signals = @import("../sched/signals.zig");
const kernel = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;

pub fn doExitGroup(error_code: i32) !u32 {
    kernel.logger.INFO("before\n", .{});
    const lock_state = kernel.task.current.thread_data.?.lock.lock_irq_disable();
    kernel.logger.INFO("after\n", .{});

    const list = &tsk.current.thread_data.?.threads;
    var it = list.iterator();
    _ = it.next();
    var prev = list;
    while (it.next()) |node| {
        if (prev == node.curr)
            break;
        prev = node.curr;
        kernel.logger.INFO("curr {x} list {x}\n", .{@intFromPtr(node.curr), @intFromPtr(list)});

        const task = node.curr.entry(kernel.task.Task, "thread_node");
        if (task == tsk.current)
            continue;

        task.sigpending.setSignal(kernel.signals.Signal.SIGKILL);
        if (task.state != .ZOMBIE and task.state != .STOPPED)
            task.state = .RUNNING;
    }

    kernel.task.current.thread_data.?.lock.unlock_irq_enable(lock_state);
    _ = doExit(error_code) catch {};
    @panic("Exit: task executed after exit finished\n");
}

pub fn doExit(error_code: i32) !u32 {
    if (tsk.current == &tsk.initial_task)
        return errors.EINVAL;

    tsk.current.result = error_code;

    kernel.fs.procfs.deleteProcess(kernel.task.current);
    kernel.task.current.refcount.put();
    while (kernel.task.current.refcount.getValue() > 1)
        arch.archReschedule();

    tsk.current.releaseSharedResources();
    const lock_state = kernel.task.tasks_lock.lock_irq_disable();

    if (tsk.current.group_leader.tree.parent) |p| {
        const parent = p.entry(tsk.Task, "tree");
        const parent_handlers = parent.getSighandOrPanic();
        const act = parent_handlers.actions.get(.SIGCHLD);

        tsk.current.state = .ZOMBIE;
        if (act.flags & signals.SA_NOCLDWAIT != 0) {
            tsk.current.refcount.get();
            tsk.current.finish(true);
        }

        if (kernel.task.current.thread_data != null) {
            tsk.current.wakeupParent(true);
            if (act.handler.handler != signals.sigIGN)
                // Check if its the last thread of the thread group
                // and only then send the signal
                // Additional: instead of checking SIGCHILD check
                // @enumFromInt(task->exit_signal)
                parent.thread_data.?.pending.setSignal(.SIGCHLD);
        }
    }
    kernel.task.tasks_lock.unlock_irq_enable(lock_state);
    sched.reschedule();
    return 0;
}

pub fn exit(error_code: i32) !u32 {
    return try doExit((error_code & 0xff) << 8);
}

pub fn exit_group(error_code: i32) !u32 {
    return try doExitGroup((error_code & 0xff) << 8);
}
