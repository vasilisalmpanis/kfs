const tsk = @import("../sched/task.zig");
const krn = @import("../main.zig");
const arch = @import("arch");
const errors = @import("../main.zig").errors;

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

pub fn wait(_: *arch.Regs, pid_arg: u32, stat_addr_arg: u32, options: u32, rusage_arg: u32) i32 {
    const pid: i32 = @intCast(pid_arg);
    const stat_addr: ?*i32 = @ptrFromInt(stat_addr_arg);
    const rusage: ?*Rusage = @ptrFromInt(rusage_arg);
    _ = rusage;
    _ = stat_addr;
    _ = options;
    krn.logger.DEBUG("waiting pid {d} from pid {d}", .{pid, tsk.current.pid});
    if (pid > 0) {
        if (tsk.current.findByPid(pid_arg)) |task| {
            defer task.refcount.unref();
            if (task.pid == tsk.current.pid) {
                return -errors.ECHILD;
            }
            while (task.state != .STOPPED) {}
            return task.result;
        } else {
            return -errors.ECHILD;
        }
    }
    return 0;
}
