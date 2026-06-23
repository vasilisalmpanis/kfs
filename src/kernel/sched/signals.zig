const tsk = @import("./task.zig");
const krn = @import("../main.zig");
const std = @import("std");
const arch = @import("arch");

pub const NSIG: u8 = 64;

pub const Sigval = extern union {
    int: i32,
    ptr: *anyopaque,
};

pub const SigAltStack = extern struct {
    sp: u32 = 0,
    flags: u32 = 0,
    size: usize = 0,
};

const SigContext = extern struct {
        gs: u16 = 0,
        __gsh: u16 = 0,
	fs: u16 = 0,
	__fsh: u16 = 0,
	es: u16 = 0,
	__esh: u16 = 0,
	ds: u16 = 0,
	__dsh: u16 = 0,
	edi: u32 = 0,
	esi: u32 = 0,
	ebp: u32 = 0,
	esp: u32 = 0,
	ebx: u32 = 0,
	edx: u32 = 0,
	ecx: u32 = 0,
	eax: u32 = 0,
	trapno: u32 = 0,
	err: u32 = 0,
	eip: u32 = 0,
	cs: u16 = 0,
        __csh: u16 = 0,
	eflags: u32 = 0,
	esp_at_signal: u32 = 0,
	ss: u16 = 0,
        __ssh: u16 = 0,
	fpstate: u32 = 0,
	oldmask: u32 = 0,
	cr2: u32 = 0,
};

pub const Ucontext = extern struct {
    flags: u32 = 0,
    link: ?*@This() = null,
    stack: SigAltStack = SigAltStack{},
    mcontext: SigContext = SigContext{},
    mask: sigset_t = .{ ._bits = .{0, 0} },

    pub fn setRegs(self: *Ucontext, regs: *arch.Regs) void {
        self.mcontext.gs  = @truncate(regs.gs);
        self.mcontext.fs  = @truncate(regs.fs);
        self.mcontext.es  = @truncate(regs.es);
        self.mcontext.ds  = @truncate(regs.ds);
        self.mcontext.edi = regs.edi;
        self.mcontext.esi = regs.esi;
        self.mcontext.ebp = regs.ebp;
        self.mcontext.esp = regs.useresp;          // user esp
        self.mcontext.ebx = regs.ebx;
        self.mcontext.edx = regs.edx;
        self.mcontext.ecx = regs.ecx;
        self.mcontext.eax = @bitCast(regs.eax);
        self.mcontext.trapno = @bitCast(regs.orig_eax);
        self.mcontext.err = regs.err_code;
        self.mcontext.eip = regs.eip;              // <-- the field the handler reads as MC_PC
        self.mcontext.cs  = @truncate(regs.cs);
        self.mcontext.eflags = regs.eflags;
        self.mcontext.esp_at_signal = regs.useresp;
        self.mcontext.ss  = @truncate(regs.ss);
        // Todo save fpu state and restore it
	self.mcontext.fpstate = 0;
        // TODO this code is ARCH dependent and restoring of oldmask depends on it
        // move to arch together with sigreturn and use it to reflect changes of
        // userspace.
	self.mcontext.oldmask = krn.task.current.sigmask._bits[0];
        self.mcontext.cr2 = arch.vmm.getCR2();
    }
};

pub const SiginfoFieldsUnion = extern union {
    pad: [128 - 2 * @sizeOf(c_int) - @sizeOf(c_long)]u8,
    common: extern struct {
        first: extern union {
            piduid: extern struct {
                pid: u32 = 0,
                uid: u32 = 0,
            },
            timer: extern struct {
                timerid: i32 = 0,
                overrun: i32 = 0,
            },
        },
        second: extern union {
            value: Sigval,
            sigchld: extern struct {
                status: i32,
                utime: isize,
                stime: isize,
            },
        },
    },
    sigfault: extern struct {
        addr: *allowzero anyopaque,
        addr_lsb: i16,
        first: extern union {
            addr_bnd: extern struct {
                lower: *anyopaque,
                upper: *anyopaque,
            },
            pkey: u32,
        },
    },
    sigpoll: extern struct {
        band: isize,
        fd: i32,
    },
    sigsys: extern struct {
        call_addr: *anyopaque,
        syscall: i32,
        native_arch: u32,
    },
};

pub const Siginfo = extern struct {
    signo: i32,
    errno: i32,
    code: i32,
    fields: SiginfoFieldsUnion,
};

pub const sigset_t = extern struct {
    _bits: [2]u32,

    pub fn init() sigset_t {
        return sigset_t {
            ._bits = .{0} ** 2,
        };
    }

    pub fn toU64(self: *const sigset_t) u64 {
        return @as(u64, self._bits[0]) | (@as(u64, self._bits[1]) << 32);
    }

    pub fn fromU64(val: u64) sigset_t {
        return sigset_t{ ._bits = .{
            @truncate(val),
            @truncate(val >> 32),
        } };
    }

    pub fn sigAddSet(self: *sigset_t, signal: Signal) void {
        const idx = signal.toInt();
        self._bits[idx / 32] |= (@as(u32, 1) << @intCast(idx % 32));
    }

    pub fn sigDelSet(self: *sigset_t, signal: Signal) void {
        const idx = signal.toInt();
        self._bits[idx / 32] &= ~(@as(u32, 1) << @intCast(idx % 32));
    }

    pub fn sigIsSet(self: *const sigset_t, signal: Signal) bool {
        const idx = signal.toInt();
        return (self._bits[idx / 32] & (@as(u32, 1) << @intCast(idx % 32))) != 0;
    }
};

pub const HandlerFn = *align(1) const fn (i32) callconv(.c) void;
pub const SigactionFn = *const fn (i32, *const Siginfo, ?*anyopaque) callconv(.c) void;
pub const RestorerFn = *const fn () callconv(.c) void;

pub const Sigaction = extern struct {
    handler: extern union {
        handler: ?HandlerFn,
        sigaction: ?SigactionFn,
    },
    flags: u32,
    restorer: ?RestorerFn = null,
    mask: sigset_t = sigset_t.init(),

};

pub const SA_NOCLDSTOP: u32  = 0x00000001; // Don't send SIGCHLD when children stop
pub const SA_NOCLDWAIT: u32  = 0x00000002; // Don't create zombie processes
pub const SA_NODEFER  : u32  = 0x40000000; // Don't block the signal during its handler
pub const SA_RESETHAND: u32  = 0x80000000; // Reset handler to default after one use
pub const SA_RESTART  : u32  = 0x10000000; // Restart syscall if possible after handler
pub const SA_SIGINFO  : u32  = 0x00000004; // Use sa_sigaction instead of sa_handler
pub const SA_ONSTACK  : u32  = 0x08000000; // Deliver the signal on the alternate stack

pub const SS_ONSTACK   : u32 = 1;          // Currently executing on the alt stack
pub const SS_DISABLE   : u32 = 2;          // Alt stack is disabled

pub const MINSIGSTKSZ: usize = 2048;
pub const SIGSTKSZ: usize = 8192;

pub const sigDFL: ?HandlerFn = @ptrFromInt(0);
pub const sigIGN: ?HandlerFn = @ptrFromInt(1);
// pub const sigERR: ?HandlerFn = @ptrFromInt(-1);

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
    //                 Default action      comment                     posix      num
    SIGHUP = 0,     // Terminate   Hang up controlling terminal or      Yes        1
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

    // RT
    SIGRT00, SIGRT01, SIGRT02, SIGRT03, SIGRT04, SIGRT05, SIGRT06, SIGRT07,
    SIGRT08, SIGRT09, SIGRT10, SIGRT11, SIGRT12, SIGRT13, SIGRT14, SIGRT15,
    SIGRT16, SIGRT17, SIGRT18, SIGRT19, SIGRT20, SIGRT21, SIGRT22, SIGRT23,
    SIGRT24, SIGRT25, SIGRT26, SIGRT27, SIGRT28, SIGRT29, SIGRT30, SIGRT31,

    pub inline fn sigsetMask(sig: Signal) u64 {
        const mask = @as(u64, 1) << @intCast(sig.toInt());
        return mask;
    }

    pub inline fn fromInt(sig: usize) Signal {
        return @enumFromInt(sig);
    }

    pub inline fn toInt(sig: Signal) usize {
        return @intFromEnum(sig);
    }

    pub inline fn toPosix(self: Signal) usize {
        return @intFromEnum(self) + 1;
    }

    pub inline fn fromPosix(num: usize) Signal {
        return @enumFromInt(num - 1);
    }
};

fn sigHandler(signum: u8) void {
    _ = signum;
    krn.logger.WARN("Default signal handler\n", .{});
}

fn sigIgn(_: u8) void {
    return;
}

const SigRes = struct {
    action: Sigaction,
    signal: u32,
};

pub const SigPending = struct {
    set: std.StaticBitSet(NSIG) = std.StaticBitSet(NSIG).initEmpty(),

    pub fn init() SigPending{
        return SigPending{
            .set = std.StaticBitSet(NSIG).initEmpty(),
        };
    }

    pub inline fn setSignal(self: *SigPending, signal: Signal) void {
        self.set.set(signal.toInt());
    }

    pub inline fn getRaw(self: *SigPending) u64 {
        return @bitCast(self.set);
    }
};

pub const SigHand = struct {
    actions: std.EnumArray(Signal, Sigaction) = blk: {
        var arr = std.EnumArray(Signal, Sigaction).initFill(default_sigaction);
        arr.set(.SIGCHLD, ignore_sigaction);
        break :blk arr;
    },
    ref: krn.RefCount = krn.RefCount.init(),

    pub fn init() SigHand {
        return SigHand{};
    }

    fn release(ref: *krn.RefCount) void {
        const hand: *SigHand = @fieldParentPtr("ref", ref);
        krn.mm.kfree(hand);
    }

    /// Allocates and returns a new SigHand structure
    /// set with the default dispositions based on POSIX.
    /// The structure returned has been already reffed.
    pub fn new() !*SigHand {
        if (krn.mm.kmalloc(SigHand)) |hand| {
            hand.* = SigHand.init();
            hand.ref.dropFn = release;

            // Start count with 1
            hand.ref.get();
            return hand;
        }
        return krn.errors.PosixError.ENOMEM;
    }

    pub fn dup(self: *SigHand)  !*SigHand {
        const new_hand = try SigHand.new();
        new_hand.actions = self.actions;
        return new_hand;
    }

    pub fn deliverSignal(self: *SigHand) ?SigRes {
        const lock_state = krn.task.current.thread_data.?.lock.lock_irq_disable();
        defer krn.task.current.thread_data.?.lock.unlock_irq_enable(lock_state);

        const static_bit: std.StaticBitSet(NSIG) = krn.task.current.getRealPending();
        var iterator = static_bit.iterator(.{});

        while (iterator.next()) |i| {
            if (krn.task.current.sigpending.set.isSet(i)) {
                krn.task.current.sigpending.set.toggle(i);
            } else {
                krn.task.current.thread_data.?.pending.set.toggle(i);
            }
            const signal = Signal.fromInt(i);
            const action = self.actions.get(signal);

            if (action.handler.handler == sigIGN) {
                return .{.action = ignore_sigaction, .signal = i};
            } else if (action.handler.handler == sigDFL) {
                return .{.action = default_sigaction, .signal = i};
            } else {
                if (action.flags & SA_RESETHAND > 0) {
                    var reset = action;
                    reset.handler.handler = sigDFL;
                    self.actions.set(signal, reset);
                }
                return .{.action = action, .signal = i};
            }
        }
        return null;
    }
};

fn setupSiginfo(ptr: u32, sig: u32, siginfo: ?*Siginfo) void {
    const arr: [*]u8 = @ptrFromInt(ptr);
    @memset(arr[0..@sizeOf(Siginfo)], 0);

    const _siginfo: *Siginfo = @ptrFromInt(ptr);
    if (siginfo) |s| {
        _siginfo.* = s.*;
    } else {
        _siginfo.signo = @intCast(sig + 1);
    }
}

fn setupUcontext(ptr: u32, ucontext: ?*Ucontext) void {
    const arr: [*]u8 = @ptrFromInt(ptr);
    @memset(arr[0..@sizeOf(Ucontext)], 0);

    const _ucontext: *Ucontext = @ptrFromInt(ptr);
    if (ucontext) |u| {
        _ucontext.* = u.*;
    } else {
        _ucontext.mask._bits[0] = krn.task.current.sigmask._bits[0];
        _ucontext.mask._bits[1] = krn.task.current.sigmask._bits[1];
    }
}

pub fn onSigStack(sp: u32) bool {
    const alt = krn.task.current.altstack;
    if (alt.size == 0)
        return false;
    return sp > alt.sp and (sp - alt.sp) <= @as(u32, @intCast(alt.size));
}

fn altStackFlags(sp: u32) u32 {
    if (krn.task.current.altstack.size == 0)
        return SS_DISABLE;
    return if (onSigStack(sp)) SS_ONSTACK else 0;
}

fn sigFrameTop(regs: *arch.Regs, action: Sigaction) u32 {
    const alt = krn.task.current.altstack;
    if (action.flags & SA_ONSTACK != 0
        and alt.size != 0
        and !onSigStack(regs.useresp))
    {
        const top: u32 = alt.sp + @as(u32, @intCast(alt.size));
        // return top & ~@as(u32, 0xf);
        return top;
    }
    return regs.useresp;
}

fn setupHandlerFnFrame(
    regs: *arch.Regs,
    result: SigRes,
    ucontext: *Ucontext,
) void {
    // TODO: removed saved regs from userspace stack its not neccessary because
    // its already present in ucontext
    const returnAddrSize: u32 = 4 + 4 + 4 + 4 + @sizeOf(arch.Regs) + @sizeOf(Siginfo) + @sizeOf(Ucontext);
    const frame_top: u32 = sigFrameTop(regs, result.action);
    const saved_regs: *arch.Regs = @ptrFromInt(frame_top - returnAddrSize + 16);
    const regs_ptr: u32 = @intFromPtr(saved_regs);

    saved_regs.* = regs.*;
    regs.eip = @intFromPtr(result.action.handler.sigaction);
    regs.useresp = frame_top - returnAddrSize;

    const siginfo_ptr = regs_ptr + @sizeOf(arch.Regs);
    setupSiginfo(siginfo_ptr, result.signal, null);

    const ucontext_ptr = siginfo_ptr + @sizeOf(Siginfo);
    setupUcontext(ucontext_ptr, ucontext);
    const _ucontext: *Ucontext = @ptrFromInt(ucontext_ptr);
    if (krn.errors.fromErrno(regs.eax) == krn.errors.PosixError.ERESTARTSYS) {
        if (result.action.flags & SA_RESTART != 0 and regs.int_no == arch.idt.SYSCALL_INTERRUPT) {
            _ucontext.mcontext.eip -= 2;
            _ucontext.mcontext.eax = @bitCast(regs.orig_eax);
        } else {
            _ucontext.mcontext.eax = @bitCast(krn.errors.toErrno(krn.errors.PosixError.EINTR));
        }
    }

    const signal_stack: [*]u32 = @ptrFromInt(regs.useresp);
    signal_stack[0] = @intFromPtr(result.action.restorer);
    signal_stack[1] = result.signal + 1;
    signal_stack[2] = siginfo_ptr;
    signal_stack[3] = ucontext_ptr;
}

pub fn processSignals(regs: *arch.Regs, mask: sigset_t) *arch.Regs {
    if (!regs.isRing3()) {
        return regs;
    }

    const task = krn.task.current;
    if (task.sighand) |sighand| {
        if (task.hasPendingSignal()) {
            const result = sighand.deliverSignal() orelse
                return regs;
            if (result.action.handler.handler == default_sigaction.handler.handler) {
                const _regs = defaultHandler(Signal.fromInt(result.signal), regs);
                return _regs;
            }
            if (result.action.handler.handler != ignore_sigaction.handler.handler) {
                var ucontext = Ucontext{};
                ucontext.setRegs(regs);
                ucontext.mask = mask;
                ucontext.stack.sp = task.altstack.sp;
                ucontext.stack.size = task.altstack.size;
                ucontext.stack.flags = altStackFlags(regs.useresp);

                tsk.current.sigmask._bits[0] |= result.action.mask._bits[0];
                tsk.current.sigmask._bits[1] |= result.action.mask._bits[1];
                if (result.action.flags & SA_NODEFER == 0) {
                    tsk.current.sigmask.sigAddSet(Signal.fromInt(result.signal));
                }
                setupHandlerFnFrame(
                    regs,
                    result,
                    &ucontext
                );
            } else {
                if (krn.errors.fromErrno(regs.eax) == krn.errors.PosixError.ERESTARTSYS) {
                    if (regs.int_no == arch.idt.SYSCALL_INTERRUPT) {
                        regs.eax = regs.orig_eax;
                        regs.eip -= 2;
                    }
                }
            }
            // Go to signal handler
            return regs;
        } else {
            if (krn.errors.fromErrno(regs.eax) == krn.errors.PosixError.ERESTARTSYS) {
                regs.eax = krn.errors.toErrno(krn.errors.PosixError.EINTR);
            }
        }
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
            // if (task.tree.parent) |p| {
            //     const parent = p.entry(tsk.Task, "tree");
            //     const act = parent.sighand.actions.get(.SIGCHLD);
            //     if (act.handler.handler != sigIGN and (act.flags & SA_NOCLDSTOP == 0)) {
            //         parent.sighand.setSignal(.SIGCHLD);
            //         parent.state = .RUNNING;
            //     }
            // }
            task.wakeup_time = 0;
            task.state = .INTERRUPTIBLE_SLEEP;
            task.wakeupParent(false);
            krn.sched.reschedule();
            return regs;
        },
        .SIGCONT => {},
        .SIGCHLD,
        .SIGURG,
        .SIGWINCH => {},
        else => {
            arch.cpu.enableInterrupts();
            _ = krn.exit.doExitGroup((
                128 + @as(i32, @intCast(signal.toPosix()))
            ) & 0x7f) catch {};
            krn.sched.reschedule();
            return regs;
        }
    }
    return regs;
}
