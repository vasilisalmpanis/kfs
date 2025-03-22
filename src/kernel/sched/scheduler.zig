const tsk = @import("./task.zig");
const dbg = @import("debug");
const lst = @import("../utils/list.zig");
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
    var buf: ?*lst.list_head = tsk.stopped_tasks;
    if (buf == null)
        return;
    if (!tsk.tasks_mutex.trylock())
        return;
    defer tsk.tasks_mutex.unlock();
    while (true) : (buf = buf.?.next) {
        const task: *tsk.task_struct = lst.list_entry(tsk.task_struct, @intFromPtr(buf.?), "next");
        const next: ?*lst.list_head = buf.?.next.?;
        if (task == tsk.current or task.refcount != 0)
            break;
        lst.list_del(buf.?);
        tsk.stopped_tasks = next;
        task.remove_self();
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
    if (tsk.current.next.next == &tsk.current.next)
        return &tsk.initial_task;
    if (!tsk.tasks_mutex.trylock())
        return tsk.current;
    defer tsk.tasks_mutex.unlock();
    var curr: *lst.list_head = tsk.current.next.next.?;
    while (curr.next != &tsk.current.next) {
        const task: *tsk.task_struct = lst.list_entry(tsk.task_struct, @intFromPtr(curr), "next");
        if (task.state == .UNINTERRUPTIBLE_SLEEP and current_ms() >= task.wakeup_time)
            task.state = .RUNNING;
        if (task.state == .RUNNING or task.state == .ZOMBIE) {
            return task;
        }
        curr = curr.next.?;
    }
    return &tsk.initial_task;
}

pub export fn schedule(state: *regs) *regs {
    if (tsk.initial_task.next.next == &tsk.initial_task.next) {
        return state;
    }
    process_tasks();
    return switch_to(tsk.current, find_next_task(), state);
}

pub fn reschedule() void {
    arch_reschedule();
}
