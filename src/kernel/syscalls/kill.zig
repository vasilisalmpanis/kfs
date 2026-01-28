const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const signals = @import("../sched/signals.zig");

fn send_signal(task: *tsk.Task, signal: signals.Signal) !u32 {
    if (tsk.current.uid != task.uid)
        return errors.EPERM;
    if (signal != .EMPTY) {
        task.sighand.setSignal(signal);
        if (
            task.state != .ZOMBIE
            and task.state != .STOPPED
            and task.state != .UNINTERRUPTIBLE_SLEEP
        ) {
            // TODO:
            // if (signal == .SIGCONT and task.state == .INTERRUPTIBLE_SLEEP)
            //     task.wakeupParent();
            task.state = .RUNNING;
        }
    }
    return 0;
}

pub fn kill(pid: i32, sig: u32) !u32 {
    const signal: signals.Signal = @enumFromInt(sig);
    if (pid == 0 or pid < -1) {
        tsk.tasks_mutex.lock();
        var it = tsk.initial_task.list.iterator();
        var count: i32 = 0;
        const pgroup: u32 = if (pid < -1) @intCast(-pid) else tsk.current.pgid;
        while (it.next()) |i| {
            const task = i.curr.entry(tsk.Task, "list");
            if (task.pgid == pgroup) {
                _ = send_signal(task, signal) catch {};
            }
            count += 1;
        }
        tsk.tasks_mutex.unlock();
        return if (count == 0) errors.ESRCH else 0;
    } else if (pid == -1) {
        tsk.tasks_mutex.lock();
        var it = tsk.initial_task.list.iterator();
        var count: i32 = 0;
        while (it.next()) |i| {
            const task = i.curr.entry(tsk.Task, "list");
            if (task.pid == 0 or task.pid == 1)
                continue;
            _ = send_signal(task, signal) catch {};
            count += 1;
        }
        tsk.tasks_mutex.unlock();
        return if (count == 0) errors.ESRCH else 0;
    } else if (tsk.initial_task.findByPid(@intCast(pid))) |task| {
        defer task.refcount.unref();
        return try send_signal(task, signal);
    }
    return errors.EPERM;
}

pub fn tkill(tid: i32, signal: u32) !u32 {
    return try kill(tid, signal);
}
