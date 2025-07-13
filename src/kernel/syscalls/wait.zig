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

const Timeval = packed struct {
    tv_sec: u64,
    tv_usec: u32,
};

const Rusage = packed struct {
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

pub fn wait4(pid: i32, stat_addr: ?*i32, options: u32, rusage: ?*Rusage) !u32 {
    _ = rusage;
    krn.logger.DEBUG("waiting pid {d} from pid {d}", .{pid, tsk.current.pid});
    if (pid > 0) {
        if (tsk.current.findChildByPid(@intCast(pid))) |task| {
            defer task.refcount.unref();
            while (task.state != .ZOMBIE) {
                sched.reschedule();
            }
            task.finish();
            if (stat_addr != null) {
                stat_addr.?.* = task.result;
            }
            return 0;
        } else {
            krn.logger.INFO("ERROR\n", .{});
            return errors.ECHILD;
        }
    } else if (pid == 0) {
        if (!tsk.current.refcountChildren(tsk.current.pgid, true))
            return errors.ECHILD;
        defer _ = tsk.current.refcountChildren(tsk.current.pgid, false);
        if (tsk.current.tree.hasChildren()) {
            // this is problematic if current == 0 and it has children that are threads.
            // It will block for ever. We should think about how to make userspace get pid1
            // and all threads to be direct children of initial_task.
            while (true) {
                var it = tsk.current.tree.child.?.siblingsIterator();
                while (it.next()) |i| {
                    const res = i.curr.entry(tsk.Task, "tree");
                    if (res.state == .ZOMBIE and res.pgid == tsk.current.pgid) {
                        res.finish();
                        if (stat_addr != null) {
                            stat_addr.?.* = res.result;
                        }
                        return 0;
                    }
                }
                if (options & WNOHANG > 0)
                    break;
                sched.reschedule();
            }
        }
    } else if (pid == -1) {
        if (!tsk.current.refcountChildren(0, true))
            return errors.ECHILD;
        defer _ = tsk.current.refcountChildren(0, false);
        if (tsk.current.tree.hasChildren()) {
            while (true) {
                var it = tsk.current.tree.child.?.siblingsIterator();
                while (it.next()) |i| {
                    const res = i.curr.entry(tsk.Task, "tree");
                    if (res.state == .ZOMBIE) {
                        res.finish();
                        if (stat_addr != null) {
                            stat_addr.?.* = res.result;
                        }
                        return 0;
                    }
                }
                if (options & WNOHANG > 0)
                    break;
                sched.reschedule();
            }
        }
    } else {
        const pgid: u32 = @intCast(-pid);
        if (!tsk.current.refcountChildren(pgid, true))
            return errors.ECHILD;
        defer _ = tsk.current.refcountChildren(pgid, false);
        if (tsk.current.tree.hasChildren()) {
            while (true) {
                var it = tsk.current.tree.child.?.siblingsIterator();
                while (it.next()) |i| {
                    const res = i.curr.entry(tsk.Task, "tree");
                    if (res.state == .ZOMBIE and pgid == res.pgid) {
                        res.finish();
                        if (stat_addr != null) {
                            stat_addr.?.* = res.result;
                        }
                        return 0;
                    }
                }
                if (options & WNOHANG > 0)
                    break;
                sched.reschedule();
            }
        } else {
        }
    }
    return 0;
}
