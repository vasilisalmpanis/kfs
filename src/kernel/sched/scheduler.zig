const tsk = @import("./task.zig");
const dbg = @import("debug");
const regs = @import("arch").regs;
const km = @import("../mm/kmalloc.zig");
const kthread_free_stack = @import("./kthread.zig").kthread_free_stack;
const current_ms = @import("../time/jiffies.zig").current_ms;
const arch_reschedule = @import("arch").arch_reschedule;


pub fn switch_to(from: *tsk.task_struct, to: *tsk.task_struct, state: *regs) *regs {
    from.regs = state.*;
    from.regs.esp = @intFromPtr(state);
    tsk.current = to;
    return @ptrFromInt(to.regs.esp);
}

fn process_tasks() void {
    var buf = tsk.stopped_tasks;
    if (buf == null)
        return;
    if (!tsk.tasks_mutex.trylock())
        return;
    defer tsk.tasks_mutex.unlock();
    while (true) : (buf = buf.?.next) {
        const task = buf.?.entry(tsk.task_struct, "list");
        const next = buf.?.next.?;
        if (task == tsk.current or task.refcount != 0)
            break;
        buf.?.del();
        tsk.stopped_tasks = next;
        if (task.tree.has_children()) {
            var it = task.tree.child.?.siblings_iterator();
            while (it.next()) |i| {
                i.curr.entry(tsk.task_struct, "tree").*.state = .ZOMBIE;
            }
        }
        task.tree.del();
        if (next == tsk.stopped_tasks) {
            tsk.stopped_tasks = null;
        }
        kthread_free_stack(task.stack_bottom);
        km.kfree(@intFromPtr(task));
        if (tsk.stopped_tasks == null) {
            break;
        }
    }
}

fn find_next_task() *tsk.task_struct {
    if (tsk.current.list.is_single())
        return &tsk.initial_task;
    if (!tsk.tasks_mutex.trylock())
        return tsk.current;
    defer tsk.tasks_mutex.unlock();

    var it = tsk.current.list.iterator();
    _ = it.next();
    while (it.next()) |i| {
        const task = i.curr.entry(tsk.task_struct, "list");
        if (task.state == .UNINTERRUPTIBLE_SLEEP and current_ms() >= task.wakeup_time)
            task.state = .RUNNING;
        if (task.state == .RUNNING or task.state == .ZOMBIE) {
            return task;
        }
    }
    return &tsk.initial_task;
}

pub export fn schedule(state: *regs) *regs {
    if (tsk.initial_task.list.is_single())
        return state;
    process_tasks();
    return switch_to(tsk.current, find_next_task(), state);
}

pub fn reschedule() void {
    arch_reschedule();
}
