const tsk = @import("../sched/task.zig");
const signal = @import("../sched/signals.zig");

pub fn kill(pid: u32, sig: u32) i32 {
    const task_res = tsk.initial_task.findByPid(pid);
    if (task_res) |task| {
        task.sigaction.setSignal(@enumFromInt(sig));
        return 0;
    }
    return -1;
}
