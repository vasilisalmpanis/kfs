const tsk = @import("../sched/task.zig");
const arch = @import("arch");
const sched = @import("../sched/scheduler.zig");
const signals = @import("../sched/signals.zig");
const kernel = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;

pub fn exit(error_code: i32) !u32 {
    if (tsk.current == &tsk.initial_task) return errors.EINVAL;
    const files: *kernel.fs.TaskFiles = tsk.current.files;
    var it = files.map.iterator(.{.direction = .forward, .kind = .set});
    while (it.next()) |idx| {
        if (files.fds.fetchRemove(idx)) |kv| {
            const file: *kernel.fs.File = kv.value;
            // We only call close when no one is using the file
            file.ref.unref(); // This should close and free the file if 0
        }
    }
    tsk.current.files.fds.deinit();
    tsk.current.files.map.deinit();
    tsk.current.fs.pwd.release();
    tsk.current.fs.root.release();
    if (tsk.current.mm) |_mm| {
        _mm.releaseMappings();
    }

    tsk.current.result = error_code;
    if (tsk.current.tree.parent) |p| {
        const parent = p.entry(tsk.Task, "tree");
        const act = parent.sighand.actions.get(.SIGCHLD);
        if (act.handler.handler != signals.sigIGN and (act.flags & signals.SA_NOCLDSTOP == 0)) {
            parent.sighand.setSignal(.SIGCHLD);
            parent.state = .RUNNING;
        }
    }
    tsk.current.state = .ZOMBIE;
    sched.reschedule();
    return 0;
}
