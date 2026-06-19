const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const std = @import("std");

const RobustList = extern struct {
    next: *RobustList,
};

pub const RobustListHead = extern struct {
    list: RobustList,
    futex_offset: usize,
    list_op_pending: *RobustList,
};

pub fn get_robust_list(pid: i32, _head: ?*?*RobustListHead, _len: ?*usize) !u32 {
    const len = _len orelse
        return errors.EFAULT;
    const head = _head orelse
        return errors.EFAULT;
    var task: ?*krn.task.Task = null;
    if (pid < 0) {
        return errors.ESRCH;
    } else if (pid == 0) {
        krn.task.current.refcount.get();
        task = krn.task.current;
    } else {
        const lock_state = krn.task.tasks_lock.lock_irq_disable();
        defer krn.task.tasks_lock.unlock_irq_enable(lock_state);

        const _pid: u16 = @intCast(pid);
        var it = krn.task.initial_task.list.iterator();
        while (it.next()) |i| {
            const curr = i.curr.entry(krn.task.Task, "list");
            if (curr.pid == _pid) {
                curr.refcount.get();
                task = curr;
            }
        }
        return errors.ESRCH;
    }
    if (task) |t|{
        defer t.refcount.put();
        
        len.* = @sizeOf(RobustListHead);
        head.* = t.robust_list;
        return 0;
    }
    return errors.ESRCH;
}

pub fn set_robust_list(head: *RobustListHead, len: usize) !u32 {
    if (len != @sizeOf(RobustListHead))
        return errors.EINVAL;
    krn.task.current.robust_list = head;
    @panic("Implement robust list care in exit and exec!");
    // return 0;
}
