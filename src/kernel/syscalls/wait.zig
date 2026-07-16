const tsk = @import("../sched/task.zig");
const krn = @import("../main.zig");
const arch = @import("arch");
const errors = @import("./error-codes.zig").PosixError;
const sched = @import("../sched/scheduler.zig");

const WNOHANG: u32 = 	0x00000001;
const WUNTRACED: u32 =  0x00000002;
const WSTOPPED: u32 =   WUNTRACED;
const WEXITED: u32 = 	0x00000004;
const WCONTINUED: u32 = 0x00000008;
const WNOWAIT: u32 = 	0x01000000;	// Don't reap, just poll status.

const Timeval = extern struct {
    tv_sec: u64,
    tv_usec: u32,
};

const Rusage = extern struct {
    ru_utime: Timeval,       // user CPU time used
    ru_stime: Timeval,       // system CPU time used
    ru_maxrss: usize,        // maximum resident set size
    ru_ixrss: usize,         // integral shared memory size
    ru_idrss: usize,         // integral unshared data size
    ru_isrss: usize,         // integral unshared stack size
    ru_minflt: usize,        // page reclaims (soft page faults)
    ru_majflt: usize,        // page faults (hard page faults)
    ru_nswap: usize,         // swaps
    ru_inblock: usize,       // block input operations
    ru_oublock: usize,       // block output operations
    ru_msgsnd: usize,        // IPC messages sent
    ru_msgrcv: usize,        // IPC messages received
    ru_nsignals: usize,      // signals received
    ru_nvcsw: usize,         // voluntary context switches
    ru_nivcsw: usize,        // involuntary context switches
};

const WaitStates = struct {
    exited: bool = true,
    stopped: bool = false,
    continued: bool = false,

    pub fn init(options: u32) WaitStates {
        var ret = WaitStates{};
        if (options & WSTOPPED != 0) {
            ret.stopped = true;
        }
        if (options & WCONTINUED != 0) {
            ret.continued = true;
        }
        if (options & WEXITED != 0)
            ret.exited = true;
        return ret;
    }

    pub fn isSet(self: *const WaitStates, task: *krn.task.Task) bool {
        if (task.state == .ZOMBIE and self.exited and task.thread_data.?.nr_threads == 0)
            return true;
        if (task.state == .STOPPED and self.exited) {
            return true;
        }
        // if (state == .INTERRUPTIBLE_SLEEP and self.stopped)
        //     return true;
        return false;
        // TODO: continued
    }

    pub fn status(_: *const WaitStates, task: *const krn.task.Task) i32 {
        if (task.state == .ZOMBIE)
            return task.result;
        if (task.state == .INTERRUPTIBLE_SLEEP)
            return task.result;
        // TODO: other cases
        return 0xffff;
    }
};

fn checkPIDPGID(task: *krn.task.Task, pid: u32, pgid: u32) bool {
    if (pid == 0 and pgid == 0)
        return true;
    if (pid > 0 and pid == task.pid)
        return true;
    if (pgid > 0 and pgid == task.pgid)
        return true;
    return false;
}

fn waitChildren(wstatus: ?*i32, opts: WaitStates, pid: u32, pgid: u32) !u32 {
    var waitable_children: bool = false;
    if (tsk.current.tree.hasChildren()) {
        var it = tsk.current.tree.child.?.siblingsIterator();
        while (it.next()) |i| {
            const res = i.curr.entry(tsk.Task, "tree");
            const child_pid = res.pid;

            if (!checkPIDPGID(res, pid, pgid))
                continue ;

            if (res.state == .STOPPED)
                continue ;

            waitable_children = true;

            if (opts.isSet(res)) {
                if (wstatus != null) {
                    wstatus.?.* = opts.status(res);
                }
                res.finish(true);
                return child_pid;
            }
        }
    }
    if (!waitable_children)
        return errors.ECHILD;
    return 0;
}

pub fn wait4(pid: i32, wstatus: ?*i32, options: u32, rusage: ?*Rusage) !u32 {
    _ = rusage;
    if (options & ~(WNOHANG|WUNTRACED|WCONTINUED) != 0)
        return errors.EINVAL;

    const opts = WaitStates.init(options);

    var _pid: u32 = 0;
    var _pgid: u32 = 0;
    if (pid < -1) {
        _pgid = @intCast(-pid);
    } else if (pid == -1) {
    } else if (pid == 0) {
        _pgid = krn.task.current.pgid;
    } else {
        _pid = @intCast(pid);
    }

    while (true) {
        var res: u32 = 0;

        const lock_state = krn.task.tasks_lock.lock_irq_disable();

        res = waitChildren(wstatus, opts, _pid, _pgid) catch |err| {
            krn.task.tasks_lock.unlock_irq_enable(lock_state);
            return err;
        };

        krn.task.tasks_lock.unlock_irq_enable(lock_state);
        if (res != 0 or (options & WNOHANG) != 0)
            return res;

        if (tsk.current.hasPendingSignal())
            return errors.ERESTARTSYS;

        tsk.current.wait_wq.wait(true, 0);
    }
    return 0;
}
