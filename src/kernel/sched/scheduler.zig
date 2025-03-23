const tsk = @import("./task.zig");
const dbg = @import("debug");
const Regs = @import("arch").Regs;
const km = @import("../mm/kmalloc.zig");
const kthreadStackFree = @import("./kthread.zig").kthreadStackFree;
const currentMs = @import("../time/jiffies.zig").currentMs;
const archReschedule = @import("arch").archReschedule;


fn switchTo(from: *tsk.Task, to: *tsk.Task, state: *Regs) *Regs {
    from.regs = state.*;
    from.regs.esp = @intFromPtr(state);
    tsk.current = to;
    return @ptrFromInt(to.regs.esp);
}

fn processTasks() void {
    var buf = tsk.stopped_tasks;
    if (buf == null)
        return;
    if (!tsk.tasks_mutex.trylock())
        return;
    defer tsk.tasks_mutex.unlock();
    while (true) : (buf = buf.?.next) {
        const task = buf.?.entry(tsk.Task, "list");
        const next = buf.?.next.?;
        if (task == tsk.current or task.refcount != 0)
            break;
        buf.?.del();
        tsk.stopped_tasks = next;
        if (task.tree.hasChildren()) {
            var it = task.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                i.curr.entry(tsk.Task, "tree").*.state = .ZOMBIE;
            }
        }
        task.tree.del();
        if (next == tsk.stopped_tasks) {
            tsk.stopped_tasks = null;
        }
        kthreadStackFree(task.stack_bottom);
        km.kfree(@intFromPtr(task));
        if (tsk.stopped_tasks == null) {
            break;
        }
    }
}

fn findNextTask() *tsk.Task {
    if (tsk.current.list.is_single())
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
    if (tsk.initial_task.list.is_single())
        return state;
    processTasks();
    return switchTo(tsk.current, findNextTask(), state);
}

pub fn reschedule() void {
    archReschedule();
}
