const tsk = @import("./task.zig");
const dbg = @import("debug");
const lst = @import("../utils/list.zig");
const regs = @import("arch").regs;

pub fn switch_to(from: *tsk.task_struct, to: *tsk.task_struct, state: *regs) *regs {
    from.regs = state.*;
    from.regs.esp = @intFromPtr(state);
    tsk.current = to;
    return @ptrFromInt(to.regs.esp);
}

pub fn timer_handler(state: *regs) *regs {
    var new_state: *regs = state;
    if (tsk.initial_task.next == null) {
        return new_state;
    }
    if (tsk.current.next == null) {
        new_state = switch_to(tsk.current, &tsk.initial_task, state);
    } else {
        new_state = switch_to(tsk.current, tsk.current.next.?, state);
    }
    return new_state;
}
