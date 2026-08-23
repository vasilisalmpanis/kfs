const kernel = @import("../main.zig");
const errors = kernel.errors.PosixError;
const Rlimit = kernel.limit.Rlimit;
const Task = kernel.task.Task;

fn doPrlimit(
    task: *Task,
    resource: i32,
    new_lim: ?*Rlimit,
    old_lim: ?*Rlimit
) !u32 {
    if (resource < 0 or resource >= kernel.limit.RLIM_NLIMITS)
        return errors.EINVAL;
    if (new_lim) |lim| {
        if (lim.rlim_cur > lim.rlim_max)
            return errors.EINVAL;
    }
    // Exit will not free thread_data while we have refcount on the task
    // so parallel exit with prlimit cannot cause problems in theory.
    const thread_data = task.thread_data orelse return errors.EINVAL;
    thread_data.lock.lock();
    defer thread_data.lock.unlock();

    const rlimit = &thread_data.rlim[@intCast(resource)];
    if (old_lim) |lim| {
        lim.* = rlimit.*;
    }
    if (new_lim) |lim| {
        rlimit.* = lim.*;
    }
    return 0;
}

pub fn prlimit(pid: i32,
    resource: i32,
    new_lim: ?*Rlimit,
    old_lim: ?*Rlimit
) !u32 {
    var task: *Task = kernel.task.current();
    var found: bool = false;
    if (pid < 0)
        return errors.ESRCH;

    // If pid is 0, then the call applies to the calling process
    if (pid != 0) {
        const lock_state = kernel.task.tasks_lock.lock_irq_disable();
        defer kernel.task.tasks_lock.unlock_irq_enable(lock_state);
        var it = kernel.task.initial_task.ptr().tree.treeIterator();
        while (it.next()) |node| {
            const curr_task: *Task = node.entry(Task, "tree");
            if (curr_task.pid == pid) {
                curr_task.refcount.get();
                task = curr_task;
                found = true;
                break;
            }
        }
        if (!found)
            return errors.ESRCH;
    }
    defer if (found) task.refcount.put();
    return doPrlimit(task, resource, new_lim, old_lim);
}

pub fn setrlimit(resource: i32, rlim: ?*Rlimit) !u32 {
    return doPrlimit(kernel.task.current(), resource, rlim, null);
}

pub fn getrlimit(resource: i32, rlim: ?*Rlimit) !u32 {
    return doPrlimit(kernel.task.current(), resource, null, rlim);
}
