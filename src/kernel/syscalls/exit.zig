const tsk = @import("../sched/task.zig");
const signal = @import("../sched/signals.zig");
const errors = @import("../main.zig").errors;
const arch = @import("arch");

pub fn exit(_: *arch.Regs, error_code: u32) i32 {
    tsk.current.result = @intCast(error_code);
    tsk.finishCurrentTask();
    return 0;
}
