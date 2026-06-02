const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const signals = @import("../sched/signals.zig");

fn send_signal(_task: *tsk.Task, signal: i32, tid: u32) !u32 {
    if (_task.tsktype == .KTHREAD)
        return errors.EPERM;
    var task = _task;
    if (tid != 0) {
        if (task.thread_data) |_td| {
            task = _td.findThread(tid) orelse
                return errors.ESRCH;
        } else {
            return errors.ESRCH;
        }
    }
    if (tsk.current.uid != task.uid)
        return errors.EPERM;
    if (signal == 0)
        return 0;
    if (task.state != .ZOMBIE and task.state != .STOPPED) {
        const sig = signals.Signal.fromPosix(@intCast(signal));
        if (tid == 0) {
            task.thread_data.?.pending.setSignal(sig);
        } else {
            task.sigpending.setSignal(sig);
        }
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

/// tid == 0 - send to process
pub fn doKill(pid: i32, sig: i32, tid: u32) !u32 {
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
                _ = send_signal(task, sig, tid) catch {};
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
            if (task.pid == 0)
                continue ;
            if (tid == 0 and task.pid == 1)
                continue ;
            if (send_signal(task, sig, tid)) |_| {
                count += 1;
                if (tid != 0)
                    break ;
            } else |err| switch (err) {
                errors.ESRCH => {},
                else => {
                    count += 1;
                }
            }
        }
        return if (count == 0) errors.ESRCH else 0;
    } else if (tsk.initial_task.findByPid(@intCast(pid))) |task| {
        defer task.refcount.put();
        return try send_signal(task, sig, tid);
    }
    return errors.EPERM;
}

pub fn kill(pid: i32, sig: i32) !u32 {
    return try doKill(pid, sig, 0);
}

/// Thread-directed kill: target is identified by TID alone.
pub fn tkill(tid: i32, sig: i32) !u32 {
    if (tid <= 0)
        return errors.EINVAL;

    return try tgkill(-1, tid, sig);
}

/// Sends the signal sig to the thread with thread ID tid in thread group tgid.
/// If tgid is -1, the tgid check is skipped (used by tkill).
pub fn tgkill(tgid: i32, tid: i32, sig: i32) !u32 {
    if (tid <= 0)
        return errors.EINVAL;
    if (tgid == 0 or tgid < -1)
        return errors.EINVAL;
    return try doKill(tgid, sig, @intCast(tid));
}
