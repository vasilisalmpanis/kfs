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
    var buf: ?*tsk.task_struct = &tsk.initial_task;
    var prev: ?*tsk.task_struct = null;
    while (buf != null) : (buf = buf.?.next) {
        if (buf.?.state == .STOPPED and buf.? != tsk.current and buf.?.refcount == 0) {
            if (prev != null) {
                prev.?.next = buf.?.next;
                kthread_free_stack(buf.?.stack_bottom);
                buf.?.remove_self();
                km.kfree(@intFromPtr(buf));
                buf = prev;
            } else {
                @panic("Attempt to stop initial task!");
            }
            continue;
        }
        if (buf.?.state == .UNINTERRUPTIBLE_SLEEP and current_ms() >= buf.?.wakeup_time) {
            buf.?.state = .RUNNING;
        }
        prev = buf;
    }
}

fn find_next_task() *tsk.task_struct {
    if (tsk.current.next == null)
        return &tsk.initial_task;
    var curr: ?*tsk.task_struct = tsk.current;
    while (curr.?.next != null) : (curr = curr.?.next) {
        if (curr.?.next.?.state == .RUNNING)
            return curr.?.next.?;
    }
    return &tsk.initial_task;
}

pub export fn schedule(state: *regs) *regs {
    if (tsk.initial_task.next == null) {
        return state;
    }
    process_tasks();
    return switch_to(tsk.current, find_next_task(), state);
}

pub fn reschedule() void {
    arch_reschedule();
}
