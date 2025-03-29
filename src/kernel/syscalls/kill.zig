const tsk = @import("../sched/task.zig");
const signal = @import("../sched/signals.zig");

pub fn kill(pid: u32, sig: u32) void {
    const task_res = tsk.initial_task.findByPid(pid);
    if (task_res) |task| {
        task.sig_pending = signal.setSignal(task.sig_pending, @enumFromInt(sig));
    }
}
