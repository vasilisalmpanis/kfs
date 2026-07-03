const std = @import("std");

pub const Rlimit = extern struct {
    rlim_cur: u64,
    rlim_max: u64,
};

pub const RLIMIT_CPU        : usize = 0;   // CPU time in sec
pub const RLIMIT_FSIZE      : usize = 1;   // Maximum filesize
pub const RLIMIT_DATA       : usize = 2;   // max data size
pub const RLIMIT_STACK      : usize = 3;   // max stack size
pub const RLIMIT_CORE       : usize = 4;   // max core file size
pub const RLIMIT_RSS        : usize = 5;   // max resident set size
pub const RLIMIT_NPROC      : usize = 6;   // max number of processes
pub const RLIMIT_NOFILE     : usize = 7;   // max number of open files
pub const RLIMIT_MEMLOCK    : usize = 8;   // max locked-in-memory address space
pub const RLIMIT_AS         : usize = 9;   // address space limit
pub const RLIMIT_LOCKS      : usize = 10;  // maximum file locks held
pub const RLIMIT_SIGPENDING : usize = 11;  // max number of pending signals
pub const RLIMIT_MSGQUEUE   : usize = 12;  // maximum bytes in POSIX mqueues
pub const RLIMIT_NICE       : usize = 13;  // max nice prio allowed to raise to
pub const RLIMIT_RTPRIO     : usize = 14;  // maximum realtime priority
pub const RLIMIT_RTTIME     : usize = 15;  // timeout for RT tasks in us
pub const RLIM_NLIMITS      : usize = 16;

const RLIM_INFINITY: u64 = std.math.maxInt(u64);

const MB           : u64 = 1024 * 1024;
const _STK_LIM     : u64 = 8 * MB;
const INR_OPEN_CUR : u64 = 1024;
const INR_OPEN_MAX : u64 = 4096;
const MLOCK_LIMIT  : u64 = 8 * MB;
const MQ_BYTES_MAX : u64 = 819200;

pub const default_rlimits: [RLIM_NLIMITS]Rlimit = .{
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // CPU
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // Filesize
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // Data size
    Rlimit{ .rlim_cur = _STK_LIM     , .rlim_max = RLIM_INFINITY },  // Stack size
    Rlimit{ .rlim_cur = 0            , .rlim_max = RLIM_INFINITY },  // Core file size
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // Resident set size
    Rlimit{ .rlim_cur = 0            , .rlim_max = 0             },  // Num of processes
    Rlimit{ .rlim_cur = INR_OPEN_CUR , .rlim_max = INR_OPEN_MAX  },  // Open files
    Rlimit{ .rlim_cur = MLOCK_LIMIT  , .rlim_max = MLOCK_LIMIT   },  // Locked-in-memory address space
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // Address space
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // File locks held
    Rlimit{ .rlim_cur = 0            , .rlim_max = 0             },  // Pending signals
    Rlimit{ .rlim_cur = MQ_BYTES_MAX , .rlim_max = MQ_BYTES_MAX  },  // Bytes in POSIX mqueues
    Rlimit{ .rlim_cur = 0            , .rlim_max = 0             },  // Nice prio allowed to raise to
    Rlimit{ .rlim_cur = 0            , .rlim_max = 0             },  // Realtime prio
    Rlimit{ .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY },  // Timeout for RT tasks
};
