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

fn processTasks() void {
    if (tsk.stopped_tasks == null)
        return;
    tsk.tasks_lock.lock();
    defer tsk.tasks_lock.unlock();

    var it = tsk.stopped_tasks.?.iterator();
    while (it.next()) |i| {
        var end: bool = false;
        const curr = i.curr;
        const task = curr.entry(tsk.Task, "list");
        if (task == tsk.current or !task.refcount.isFree() or task.state == .ZOMBIE)
            continue;
        if (curr.isEmpty()) {
            end = true;
            tsk.stopped_tasks = null;
        } else {
            it = curr.next.?.iterator();
            if (curr == tsk.stopped_tasks)
                tsk.stopped_tasks = curr.next;
        }
        curr.del();
        task.delFromTree(); // Already done in task finish but safe
        if (task.mm) |_mm| _mm.delete();
        kthreadStackFree(task.stack_bottom);
        tsk.releasePid(task.pid);
        km.kfree(task);
        if (end)
            break;
    }
}

fn findNextTask() *tsk.Task {
    if (tsk.current.list.isEmpty())
        return &tsk.initial_task;
    tsk.tasks_lock.lock();
    defer tsk.tasks_lock.unlock();

    var it = tsk.current.list.iterator();
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
    return &tsk.initial_task;
}

pub fn schedule() void {
    if (tsk.initial_task.list.isEmpty())
        return;
    const flags = arch.cpu.saveFlagsAndCli();
    defer arch.cpu.restoreFlags(flags);
    processTasks();
    const prev = tsk.current;
    const next = findNextTask();
    if (prev != next)
        arch.contextSwitch(prev, next);
}

pub fn reschedule() void {
    if (!arch.cpu.areIntEnabled())
        return;
    schedule();
}
