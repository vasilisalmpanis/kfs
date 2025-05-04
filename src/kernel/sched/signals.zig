const tsk = @import("./task.zig");
const krn = @import("../main.zig");
const std = @import("std");
const arch = @import("arch");
pub const SIG_COUNT: u8 = 32;

pub const Sigval = union {
    int: i32,
    ptr: *anyopaque,
};

const SiginfoFieldsUnion = union {
    pad: [128 - 2 * @sizeOf(c_int) - @sizeOf(c_long)]u8,
    common: struct {
        first: union {
            piduid: struct {
                pid: u32,
                uid: u32,
            },
            timer: struct {
                timerid: i32,
                overrun: i32,
            },
        },
        second: union {
            value: Sigval,
            sigchld: struct {
                status: i32,
                utime: isize,
                stime: isize,
            },
        },
    },
    sigfault: struct {
        addr: *allowzero anyopaque,
        addr_lsb: i16,
        first: union {
            addr_bnd: struct {
                lower: *anyopaque,
                upper: *anyopaque,
            },
            pkey: u32,
        },
    },
    sigpoll: struct {
        band: isize,
        fd: i32,
    },
    sigsys: struct {
        call_addr: *anyopaque,
        syscall: i32,
        native_arch: u32,
    },
};

pub const Siginfo = struct {
    signo: i32,
    errno: i32,
    code: i32,
    fields: SiginfoFieldsUnion,
};

pub const sigset_t = [2]u32;

pub const HandlerFn = *align(1) const fn (i32) callconv(.c) void;
pub const SigactionFn = *const fn (i32, *const Siginfo, ?*anyopaque) callconv(.c) void;
pub const RestorerFn = *const fn () callconv(.c) void;

pub const Sigaction = struct {

    handler: extern union {
        handler: ?HandlerFn,
        sigaction: ?SigactionFn,
    },
    flags: c_uint,
    restorer: ?RestorerFn = null,
    mask: sigset_t,
};

// const SigHandler = fn (signum: u8) void;

const sigDFL: ?HandlerFn = @ptrFromInt(0);
const sigIGN: ?HandlerFn = @ptrFromInt(1);
const sigERR: ?HandlerFn = @ptrFromInt(-1);

const default_sigaction: Sigaction = Sigaction{
    .handler = .{ .handler = sigDFL },
    .mask = .{0} ** 2,
    .flags = 0,
    .restorer = null,
};

const ignore_sigaction: Sigaction = Sigaction{
    .handler = .{ .handler = sigIGN },
    .mask = .{0} ** 2,
    .flags = 0,
    .restorer = null,
};

const Signal = enum(u8) {
    EMPTY = 0,      // Default action      comment                     posix       0
    SIGHUP = 1,     // Terminate   Hang up controlling terminal or      Yes        1
    SIGINT,         // Terminate   Interrupt from keyboard, Control-C   Yes        2
    SIGQUIT,        // Dump        Quit from keyboard, Control-\        Yes        3
    SIGILL,         // Dump        Illegal instruction                  Yes        4
    SIGTRAP,        // Dump        Breakpoint for debugging             No         5
    SIGABRT,        // Dump        Abnormal termination                 Yes        6
    SIGIOT,         // Dump        Equivalent to SIGABRT                No         7
    SIGBUS,         // Dump        Bus error                            No         8
    SIGFPE,         // Dump        Floating-point exception           .EMPTY  Yes  9
    SIGKILL,        // Terminate   Forced-process termination           Yes        10
    SIGUSR1,        // Terminate   Available to processes               Yes        11
    SIGSEGV,        // Dump        Invalid memory reference             Yes        12
    SIGUSR2,        // Terminate   Available to processes               Yes        13
    SIGPIPE,        // Terminate   Write to pipe with no readers        Yes        14
    SIGALRM,        // Terminate   Real-timer clock                     Yes        15
    SIGTERM,        // Terminate   Process termination                  Yes        16
    SIGSTKFLT,      // Terminate   Coprocessor stack error              No         17
    SIGCHLD,        // Ignore      Child process stopped or terminated  Yes        18
    SIGCONT,        // Continue    Resume execution, if stopped         Yes        19
    SIGSTOP,        // Stop        Stop process execution, Ctrl-Z       Yes        20
    SIGTSTP,        // Stop        Stop process issued from tty         Yes        21
    SIGTTIN,        // Stop        Background process requires input    Yes        22
    SIGTTOU,        // Stop        Background process requires output   Yes        23
    SIGURG,         // Ignore      Urgent condition on socket           No         24
    SIGXCPU,        // Dump        CPU time limit exceeded              No         25
    SIGXFSZ,        // Dump        File size limit exceeded             No         26
    SIGVTALRM,      // Terminate   Virtual timer clock                  No         27
    SIGPROF,        // Terminate   Profile timer clock                  No         28
    SIGWINCH,       // Ignore      Window resizing                      No         29
    SIGIO,          // Terminate   I/O now possible                     No         30
    SIGPOLL,        // Terminate   Equivalent to SIGIO                  No         31
    SIGPWR,         // Terminate   Power supply failure                 No         32
    SIGSYS,         // Dump        Bad system call                      No         33
    SIGUNUSED,      // Dump        Equivalent to SIGSYS                 No         34
};

fn sigHandler(signum: u8) void {
    _ = signum;
    krn.logger.WARN("Default signal handler\n", .{});
}

fn sigHup(_: u8) void {
    // Terminating.
    tsk.tasks_mutex.lock();
    tsk.current.state = .STOPPED;
    tsk.current.list.del();
    if (tsk.stopped_tasks == null) {
        tsk.stopped_tasks = &tsk.current.list;
        tsk.stopped_tasks.?.setup();
    } else {
        tsk.stopped_tasks.?.addTail(&tsk.current.list);
    }
    tsk.tasks_mutex.unlock();
}

fn sigIgn(_: u8) void {
    return;
}

pub const SigHand = struct {
    processing: bool = false,
    pending: std.StaticBitSet(32) = std.StaticBitSet(32).initEmpty(),
    context: arch.Regs = arch.Regs.init(),
    actions: std.EnumArray(Signal, Sigaction) =
        std.EnumArray(Signal, Sigaction).init(.{
            .EMPTY      = default_sigaction,
            .SIGHUP     = default_sigaction,
            .SIGINT     = default_sigaction,
            .SIGQUIT    = default_sigaction,
            .SIGILL     = default_sigaction,
            .SIGTRAP    = default_sigaction,
            .SIGABRT    = default_sigaction,
            .SIGIOT     = default_sigaction,
            .SIGBUS     = default_sigaction,
            .SIGFPE     = default_sigaction,
            .SIGKILL    = default_sigaction,
            .SIGUSR1    = default_sigaction,
            .SIGSEGV    = default_sigaction,
            .SIGUSR2    = default_sigaction,
            .SIGPIPE    = default_sigaction,
            .SIGALRM    = default_sigaction,
            .SIGTERM    = default_sigaction,
            .SIGSTKFLT  = default_sigaction,
            .SIGCHLD    = ignore_sigaction,
            .SIGCONT    = default_sigaction,
            .SIGSTOP    = default_sigaction,
            .SIGTSTP    = default_sigaction,
            .SIGTTIN    = default_sigaction,
            .SIGTTOU    = default_sigaction,
            .SIGURG     = default_sigaction,
            .SIGXCPU    = default_sigaction,
            .SIGXFSZ    = default_sigaction,
            .SIGVTALRM  = default_sigaction,
            .SIGPROF    = default_sigaction,
            .SIGWINCH   = default_sigaction,
            .SIGIO      = default_sigaction,
            .SIGPOLL    = default_sigaction,
            .SIGPWR     = default_sigaction,
            .SIGSYS     = default_sigaction,
            .SIGUNUSED  = default_sigaction,
        }),
    
    pub fn init() SigHand {
        return SigHand{};
    }

    pub fn deliverSignal(self: *SigHand) Sigaction {
        var it = self.pending.iterator(.{});
        while (it.next()) |i| {
            self.pending.toggle(i);
            const signal: Signal = @enumFromInt(i);
            const action = self.actions.get(signal);
            if (action.handler.handler == sigIGN) {
                continue;
            } else if (action.handler.handler == sigDFL) {
                return default_sigaction;
            } else {
                return action;
            }
        }
        self.processing = false;
        return default_sigaction;
    }

    pub fn setSignal(self: *SigHand, signal: Signal) void {
        self.pending.set(@intFromEnum(signal));
    }

    pub fn isReady(self: *SigHand) bool {
        if (self.processing)
            return false;
        if (self.pending.count() != 0) {
            self.processing = true;
            return true;
        }
        return false;
    }
};

pub fn processSignals(task: *tsk.Task) void {
    if (task.sighand.isReady()) {
        const regs: *arch.Regs = @ptrFromInt(task.regs.esp);
        // const eip: u32 = regs.eip; // userspace eip

        const action = task.sighand.deliverSignal();
        if (action.handler.handler == default_sigaction.handler.handler)
            return;
        task.sighand.context = regs.*;
        regs.eip = @intFromPtr(action.handler.handler);

        const returnAddrSize: u32 = 4 + 4;
        regs.useresp -= returnAddrSize;

        const signal_stack: [*]u32 = @ptrFromInt(regs.useresp);
        signal_stack[0] = @intFromPtr(action.restorer);
        signal_stack[1] = 10;
    }
}
