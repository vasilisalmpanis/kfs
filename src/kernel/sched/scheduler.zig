const tsk = @import("./task.zig");
const dbg = @import("debug");
const Regs = @import("arch").Regs;
const km = @import("../mm/kmalloc.zig");
const kthreadStackFree = @import("./kthread.zig").kthreadStackFree;
const currentMs = @import("../time/jiffies.zig").currentMs;
const archReschedule = @import("arch").archReschedule;
const signalWrapper = @import("./signals.zig").signalWrapper;


fn switchTo(from: *tsk.Task, to: *tsk.Task, state: *Regs) *Regs {
    from.regs = state.*;
    from.regs.esp = @intFromPtr(state);
    tsk.current = to;
    if (tsk.current.sigaction.isReady()) {
        tsk.current.sigaction.saveTaskRegs(to.regs.esp);
        const regs: *Regs = @ptrFromInt(to.regs.esp);
        tsk.current.sig_eip = regs.eip;
        regs.eip = @intFromPtr(&signalWrapper);
    }
    return @ptrFromInt(to.regs.esp);
}

fn processTasks() void {
    if (tsk.stopped_tasks == null)
        return;
    if (!tsk.tasks_mutex.trylock())
        return;
    defer tsk.tasks_mutex.unlock();
    var it = tsk.stopped_tasks.?.iterator();
    while (it.next()) |i| {
        var end: bool = false;
        const curr = i.curr;
        const task = curr.entry(tsk.Task, "list");
        if (task == tsk.current or task.refcount != 0)
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
        task.delFromTree();
        kthreadStackFree(task.stack_bottom);
        km.kfree(@intFromPtr(task));
        if (end)
            break;
    }
}

fn findNextTask() *tsk.Task {
    if (tsk.current.list.isEmpty())
        return &tsk.initial_task;
    if (!tsk.tasks_mutex.trylock())
        return tsk.current;
    defer tsk.tasks_mutex.unlock();

    var it = tsk.current.list.iterator();
    _ = it.next();
    while (it.next()) |i| {
        const task = i.curr.entry(tsk.Task, "list");
        if (task.state == .UNINTERRUPTIBLE_SLEEP and currentMs() >= task.wakeup_time)
            task.state = .RUNNING;
        if (task.state == .RUNNING or task.state == .ZOMBIE) {
            return task;
        }
    }
    return &tsk.initial_task;
}

pub export fn schedule(state: *Regs) *Regs {
    if (tsk.initial_task.list.isEmpty())
        return state;
    processTasks();
    return switchTo(tsk.current, findNextTask(), state);
}

pub fn reschedule() void {
    archReschedule();
}
