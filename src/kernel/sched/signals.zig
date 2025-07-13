const tsk = @import("./task.zig");
const krn = @import("../main.zig");
const std = @import("std");
const arch = @import("arch");
pub const SIG_COUNT: u8 = 32;

pub const Sigval = union {
    int: i32,
    ptr: *anyopaque,
};

const SigAltStack = struct {
    sp: *anyopaque,
    flags: i32,
    size: usize,
};

const SigContext = struct {
    gs: u16,
	fs: u16,
	es: u16,
	ds: u16,
	edi: u32,
	esi: u32,
	ebp: u32,
	esp: u32,
	ebx: u32,
	edx: u32,
	ecx: u32,
	eax: u32,
	trapno: u32,
	err: u32,
	eip: u32,
	cs: u16,
    __csh: u16,
	eflags: u32,
	esp_at_signal: u32,
	ss: u16,
    __ssh: u16,
	fpstate: u32,
	oldmask: u32,
	cr2: u32,
};

const Ucontext = struct {
    flags: u32,
    link: *@This(),
    stack: SigAltStack,
    mcontext: SigContext,
    mask: sigset_t,
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

pub const sigset_t = struct {
    _bits: [2]u32,

    pub fn init() sigset_t {
        return sigset_t {
            ._bits = .{0} ** 2,
        };
    }

    pub fn sigAddSet(self: *sigset_t, signal: Signal) void {
        self._bits[0] |= sigmask(signal);
    }

    pub fn sigDelSet(self: *sigset_t, signal: Signal) void {
        self._bits[0] &= ~sigmask(signal);
    }

    pub fn sigIsSet(self: *const sigset_t, signal: Signal) bool {
        return self._bits[0] & sigmask(signal) != 0;
    }
};

pub const HandlerFn = *align(1) const fn (i32) callconv(.c) void;
pub const SigactionFn = *const fn (i32, *const Siginfo, ?*anyopaque) callconv(.c) void;
pub const RestorerFn = *const fn () callconv(.c) void;

pub const Sigaction = struct {
    handler: extern union {
        handler: ?HandlerFn,
        sigaction: ?SigactionFn,
    },
    flags: u32,
    restorer: ?RestorerFn = null,
    mask: sigset_t = sigset_t.init(),

};

pub fn sigmask(sig: Signal) u32 {
        const num: u32 = @intFromEnum(sig);
        const bit_index: u32 = @as(u32, 1) << @intCast(num - 1);
        return bit_index;
}

pub const SA_NOCLDSTOP: u32  = 0x00000001; // Don't send SIGCHLD when children stop
pub const SA_NOCLDWAIT: u32  = 0x00000002; // Don't create zombie processes
pub const SA_NODEFER  : u32  = 0x40000000; // Don't block the signal during its handler
pub const SA_RESETHAND: u32  = 0x80000000; // Reset handler to default after one use
pub const SA_RESTART  : u32  = 0x10000000; // Restart syscall if possible after handler
pub const SA_SIGINFO  : u32  = 0x00000004; // Use sa_sigaction instead of sa_handler

pub const sigDFL: ?HandlerFn = @ptrFromInt(0);
pub const sigIGN: ?HandlerFn = @ptrFromInt(1);
pub const sigERR: ?HandlerFn = @ptrFromInt(-1);

const default_sigaction: Sigaction = Sigaction{
    .handler = .{ .handler = sigDFL },
    .flags = 0,
    .restorer = null,
};

const ignore_sigaction: Sigaction = Sigaction{
    .handler = .{ .handler = sigIGN },
    .flags = 0,
    .restorer = null,
};

pub const Signal = enum(u8) {
    EMPTY = 0,      // Default action      comment                     posix       0
    SIGHUP = 1,     // Terminate   Hang up controlling terminal or      Yes        1
    SIGINT,         // Terminate   Interrupt from keyboard, Control-C   Yes        2
    SIGQUIT,        // Dump        Quit from keyboard, Control-\        Yes        3
    SIGILL,         // Dump        Illegal instruction                  Yes        4
    SIGTRAP,        // Dump        Breakpoint for debugging             No         5
    SIGABRT,        // Dump        Abnormal termination                 Yes        6
    SIGBUS,         // Dump        Bus error                            No         7
    SIGFPE,         // Dump        Floating-point exception           .EMPTY  Yes  8
    SIGKILL,        // Terminate   Forced-process termination           Yes        9
    SIGUSR1,        // Terminate   Available to processes               Yes        10
    SIGSEGV,        // Dump        Invalid memory reference             Yes        11
    SIGUSR2,        // Terminate   Available to processes               Yes        12
    SIGPIPE,        // Terminate   Write to pipe with no readers        Yes        13
    SIGALRM,        // Terminate   Real-timer clock                     Yes        14
    SIGTERM,        // Terminate   Process termination                  Yes        15
    SIGSTKFLT,      // Terminate   Coprocessor stack error              No         16
    SIGCHLD,        // Ignore      Child process stopped or terminated  Yes        17
    SIGCONT,        // Continue    Resume execution, if stopped         Yes        18
    SIGSTOP,        // Stop        Stop process execution, Ctrl-Z       Yes        19
    SIGTSTP,        // Stop        Stop process issued from tty         Yes        20
    SIGTTIN,        // Stop        Background process requires input    Yes        21
    SIGTTOU,        // Stop        Background process requires output   Yes        22
    SIGURG,         // Ignore      Urgent condition on socket           No         23
    SIGXCPU,        // Dump        CPU time limit exceeded              No         24
    SIGXFSZ,        // Dump        File size limit exceeded             No         25
    SIGVTALRM,      // Terminate   Virtual timer clock                  No         26
    SIGPROF,        // Terminate   Profile timer clock                  No         27
    SIGWINCH,       // Ignore      Window resizing                      No         28
    SIGIO,          // Terminate   I/O now possible                     No         29
    SIGPOLL,        // Terminate   Equivalent to SIGIO                  No         30
    SIGPWR,         // Terminate   Power supply failure                 No         31
    SIGSYS,         // Dump        Bad system call                      No         32
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

const SigRes = struct {
    action: Sigaction,
    signal: u32,
};

pub const SigHand = struct {
    pending: std.StaticBitSet(32) = std.StaticBitSet(32).initEmpty(),
    actions: std.EnumArray(Signal, Sigaction) =
        std.EnumArray(Signal, Sigaction).init(.{
            .EMPTY      = default_sigaction,
            .SIGHUP     = default_sigaction,
            .SIGINT     = default_sigaction,
            .SIGQUIT    = default_sigaction,
            .SIGILL     = default_sigaction,
            .SIGTRAP    = default_sigaction,
            .SIGABRT    = default_sigaction,
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
        }),
    
    pub fn init() SigHand {
        return SigHand{};
    }


    pub fn isBlocked(self: *SigHand, signal: Signal) bool {
        if (tsk.current.sigmask.sigIsSet(signal))
            return true;
        for(1..32) |idx| {
            const action = self.actions.get(@enumFromInt(idx));
            if (action.mask.sigIsSet(@enumFromInt(idx))) {
                if (action.mask.sigIsSet(signal))
                    return true;
            }
        }
        return false;
    }

    pub fn deliverSignal(self: *SigHand) SigRes {
        var it = self.pending.iterator(.{});
        while (it.next()) |i| {
            self.pending.toggle(i);
            const signal: Signal = @enumFromInt(i);
            var action = self.actions.get(signal);
            if (self.isBlocked(signal)) {
                self.pending.toggle(i);
                continue;
            }
            if (action.handler.handler == sigIGN) {
                continue;
            } else if (action.handler.handler == sigDFL) {
                return .{.action = default_sigaction, .signal = i};
            } else {
                if (action.flags & SA_NODEFER == 0) {
                    action.mask.sigAddSet(signal);
                    self.actions.set(signal, action);
                }
                if (action.flags & SA_RESETHAND > 0) {
                    action.handler.handler = sigDFL;
                    self.actions.set(signal, action);
                }
                return .{.action = action, .signal = i};
            }
        }
        return .{.action = default_sigaction, .signal = 0};
    }

    pub fn setSignal(self: *SigHand, signal: Signal) void {
        self.pending.set(@intFromEnum(signal));
    }

    pub fn isReady(self: *SigHand) bool {
        if (self.pending.count() != 0) {
            return true;
        }
        return false;
    }
};

fn setupHadlerFnFrame(regs: *arch.Regs, result: SigRes) void {
    const returnAddrSize: u32 = 4 + 4 + @sizeOf(arch.Regs);
    const saved_regs: *arch.Regs = @ptrFromInt(regs.useresp - returnAddrSize + 8);
    saved_regs.* = regs.*;
    regs.eip = @intFromPtr(result.action.handler.handler);
    regs.useresp -= returnAddrSize;

    const signal_stack: [*]u32 = @ptrFromInt(regs.useresp);
    signal_stack[0] = @intFromPtr(result.action.restorer);
    signal_stack[1] = result.signal;
}

fn setupSigactionFnFrame(regs: *arch.Regs, result: SigRes) void {
    const returnAddrSize: u32 = 4 + 4 + 4 + 4 + @sizeOf(arch.Regs) + @sizeOf(Siginfo) + @sizeOf(Ucontext);
    const saved_regs: *arch.Regs = @ptrFromInt(regs.useresp - returnAddrSize + 16);
    const regs_ptr: u32 = @intFromPtr(saved_regs);
    saved_regs.* = regs.*;
    regs.eip = @intFromPtr(result.action.handler.sigaction);
    regs.useresp -= returnAddrSize;

    const siginfo_ptr = regs_ptr + @sizeOf(arch.Regs);

    const siginfo_cnt: [*]u8 = @ptrFromInt(siginfo_ptr);
    @memset(siginfo_cnt[0..@sizeOf(Siginfo)], 0);

    const ucontext_ptr = siginfo_ptr + @sizeOf(Siginfo);

    const ucontext_cnt: [*]u8 = @ptrFromInt(ucontext_ptr);
    @memset(ucontext_cnt[0..@sizeOf(Ucontext)], 0);

    const signal_stack: [*]u32 = @ptrFromInt(regs.useresp);
    signal_stack[0] = @intFromPtr(result.action.restorer);
    signal_stack[1] = result.signal;
    signal_stack[2] = siginfo_ptr;
    signal_stack[3] = 0;
}

pub fn setupRegs(regs: *arch.Regs) *arch.Regs {
    if (!regs.isRing3()) {
        const uregs: *arch.Regs = @ptrFromInt(arch.gdt.tss.esp0 - @sizeOf(arch.Regs));
        regs.* = uregs.*;
        if (regs.int_no == arch.idt.SYSCALL_INTERRUPT) {
            regs.eax = krn.errors.toErrno(krn.errors.PosixError.EINTR);
        }
    }
    return regs;
}

pub fn processSignals(regs: *arch.Regs) *arch.Regs {
    const task = krn.task.current;
    if (task.sighand.isReady()) {
        const result = task.sighand.deliverSignal();
        if (result.signal == 0)
            return regs;
        if (result.action.handler.handler == default_sigaction.handler.handler)
            return defaultHandler(@enumFromInt(result.signal), regs);
        regs.* = setupRegs(regs).*;
        if (result.action.flags & SA_SIGINFO == 0) {
            setupHadlerFnFrame(regs, result);
        } else {
            setupSigactionFnFrame(regs, result);
        }
        return regs;
    }
    return regs;
}

fn defaultHandler(signal: Signal, regs: *arch.Regs) *arch.Regs {
    const task = krn.task.current;
    switch (signal) {
        .SIGSTOP,
        .SIGTSTP,
        .SIGTTIN,
        .SIGTTOU => {
            task.state = .INTERRUPTIBLE_SLEEP;
            krn.sched.reschedule();
        },
        .SIGCONT => {},
        .SIGCHLD,
        .SIGURG,
        .SIGWINCH => {},
        else => {
            task.state = .ZOMBIE;
            task.result = 128 + @intFromEnum(signal);
            // krn.sched.reschedule();
            return krn.sched.schedule(regs);
        }
    }
    return regs;
}
