const tsk = @import("./task.zig");
const dbg = @import("debug");
const lst = @import("../utils/list.zig");
const regs = @import("arch").regs;
const km = @import("../mm/kmalloc.zig");

pub fn switch_to(from: *tsk.task_struct, to: *tsk.task_struct, state: *regs) *regs {
    from.regs = state.*;
    from.regs.esp = @intFromPtr(state);
    tsk.current = to;
    return @ptrFromInt(to.regs.esp);
}

fn cleanup_stopped_tasks() void {
    var buf: ?*tsk.task_struct = &tsk.initial_task;
    var prev: ?*tsk.task_struct = null;
    while (buf != null) : (buf = buf.?.next) {
        if (buf.?.state == .STOPPED and buf.? != tsk.current) {
            if (prev != null) {
                prev.?.next = buf.?.next;
                km.kfree(buf.?.stack_bottom);
                km.kfree(@intFromPtr(buf));
            } else {
                @panic("Attempt to stop initial task!");
            }
            continue ;
        }
        prev = buf;
    }
}

pub fn timer_handler(state: *regs) *regs {
    var new_state: *regs = state;
    if (tsk.initial_task.next == null) {
        return new_state;
    }
    cleanup_stopped_tasks();
    if (tsk.current.next == null) {
        new_state = switch_to(tsk.current, &tsk.initial_task, state);
    } else {
        new_state = switch_to(tsk.current, tsk.current.next.?, state);
    }
    return new_state;
}
