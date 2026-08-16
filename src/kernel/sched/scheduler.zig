const tsk = @import("./task.zig");
const dbg = @import("debug");
const Regs = @import("arch").Regs;
const km = @import("../mm/kmalloc.zig");
const kthreadStackFree = @import("./kthread.zig").kthreadStackFree;
const STACK_SIZE = @import("./kthread.zig").STACK_SIZE;
const currentMs = @import("../time/jiffies.zig").currentMs;
const signals = @import("./signals.zig");
const std = @import("std");
const gdt = @import("arch").gdt;
const krn = @import("../main.zig");
const arch = @import("arch");

pub fn processTasks() void {
    const state = tsk.tasks_lock.lock_irq_disable();

    var task_to_free: ?*krn.task.Task = null;

    if (tsk.stopped_tasks == null) {
        tsk.tasks_lock.unlock_irq_enable(state);
        return;
    }

    var it = tsk.stopped_tasks.?.iterator();
    top_level: while (it.next()) |i| {
        const curr = i.curr;
        const task = curr.entry(tsk.Task, "list");
        if (task == tsk.current() or !task.refcount.isFree() or task.state == .ZOMBIE)
            continue;
        for (0..arch.smp.cpu_count) |logical_id| {
            if (krn.task.current_task.ptrOn(logical_id).* == task)
                continue: top_level;
        }
        if (curr.isEmpty()) {
            tsk.stopped_tasks = null;
        } else {
            it = curr.next.?.iterator();
            if (curr == tsk.stopped_tasks)
                tsk.stopped_tasks = curr.next;
        }
        curr.del();
        task.delFromTree(); // Already done in task finish but safe
        task_to_free = task;
        tsk.releasePid(task.pid);
        break;
    }
    tsk.tasks_lock.unlock_irq_enable(state);

    if (task_to_free) |to_free| {
        if (to_free.mm) |_mm| {
            if (_mm.ref.putAndTest())
                _mm.delete();
        }
        kthreadStackFree(to_free.stack_bottom);
        km.kfree(to_free);
    }
}

fn findNextTask() *tsk.Task {
    if (tsk.current().state == .STOPPED)
        return tsk.initial_task.ptr();
    if (tsk.current().list.isEmpty())
        return tsk.initial_task.ptr();
    tsk.tasks_lock.lock();
    defer tsk.tasks_lock.unlock();

    var it = tsk.current().list.iterator();
    _ = it.next();
    while (it.next()) |i| {
        const task = i.curr.entry(tsk.Task, "list");
        if (task.wakeup_time != 0 and (
                task.state == .UNINTERRUPTIBLE_SLEEP or
                task.state == .INTERRUPTIBLE_SLEEP
            ) and currentMs() >= task.wakeup_time) {
            task.wakeup_time = 0;
            task.state = .RUNNING;
        }
        if (task.state == .INTERRUPTIBLE_SLEEP and task.hasPendingSignal())
            task.state = .RUNNING;
        if (task.state == .RUNNING)
            return task;
    }
    return tsk.initial_task.ptr();
}

pub fn schedule() void {
    const flags = arch.cpu.saveFlagsAndCli();
    defer arch.cpu.restoreFlags(flags);
    const prev = tsk.current();
    const next = findNextTask();
    if (prev != next)
        arch.contextSwitch(prev, next);
}

pub fn reschedule() void {
    if (!arch.cpu.areIntEnabled())
        return;
    schedule();
}
