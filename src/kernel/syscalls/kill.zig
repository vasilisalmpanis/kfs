const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const signals = @import("../sched/signals.zig");

fn send_signal(task: *tsk.Task, signal: i32) !u32 {
    if (task.tsktype == .KTHREAD)
        return errors.EPERM;
    if (tsk.current.uid != task.uid)
        return errors.EPERM;
    if (signal == 0)
        return 0;
    if (task.state != .ZOMBIE and task.state != .STOPPED) {
        task.thread_data.?.pending.setSignal(
            signals.Signal.fromPosix(@intCast(signal))
        );
    }

    if (
        task.state != .ZOMBIE
        and task.state != .STOPPED
        and task.state != .UNINTERRUPTIBLE_SLEEP
    ) {
        // TODO:
        // if (signal == .SIGCONT and task.state == .INTERRUPTIBLE_SLEEP)
        //     task.wakeupParent(false);
        task.state = .RUNNING;
    }
    return 0;
}

pub fn kill(pid: i32, sig: i32) !u32 {
    if (sig < 0 or sig > signals.Signal.SIGSYS.toPosix())
        return errors.EINVAL;
    if (pid == 0 or pid < -1) {
        const lock_state = tsk.tasks_lock.lock_irq_disable();
        defer tsk.tasks_lock.unlock_irq_enable(lock_state);

        var it = tsk.initial_task.list.iterator();
        var count: i32 = 0;
        const pgroup: u32 = if (pid < -1) @intCast(-pid) else tsk.current.pgid;
        while (it.next()) |i| {
            const task = i.curr.entry(tsk.Task, "list");
            if (task.pgid == pgroup) {
                _ = send_signal(task, sig) catch {};
            }
            count += 1;
        }
        return if (count == 0) errors.ESRCH else 0;
    } else if (pid == -1) {
        const lock_state = tsk.tasks_lock.lock_irq_disable();
        defer tsk.tasks_lock.unlock_irq_enable(lock_state);

        var it = tsk.initial_task.list.iterator();
        var count: i32 = 0;
        while (it.next()) |i| {
            const task = i.curr.entry(tsk.Task, "list");
            if (task.pid == 0 or task.pid == 1)
                continue;
            _ = send_signal(task, sig) catch {};
            count += 1;
        }
        return if (count == 0) errors.ESRCH else 0;
    } else if (tsk.initial_task.findByPid(@intCast(pid))) |task| {
        defer task.refcount.put();
        return try send_signal(task, sig);
    }
    return errors.EPERM;
}

pub fn tkill(tid: i32, signal: i32) !u32 {
    return try kill(tid, signal);
}
