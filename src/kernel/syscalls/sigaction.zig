const tsk = @import("../sched/task.zig");
const signals = @import("../sched/signals.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const krn = @import("../main.zig");

pub fn sigaction(sig: u32, act: ?*signals.Sigaction, oact: ?*signals.Sigaction) !u32 {
    if (sig > 31)
        return errors.EINVAL;
    const signal: signals.Signal = @enumFromInt(sig);
    if (signal == .SIGKILL or signal == .SIGSTOP)
        return errors.EINVAL;
    if (oact) |old_act| {
        old_act.* = tsk.current.sighand.actions.get(signal);
    }
    if (act) |_act| {
        tsk.current.sighand.actions.set(signal, _act.*);
    }
    return 0;
}

pub fn sigreturn() !u32 {
    const signal_regs: *arch.Regs = @ptrFromInt(arch.gdt.tss.esp0 - @sizeOf(arch.Regs));
    const num: *u32 = @ptrFromInt(signal_regs.useresp - 4);
    const signal: signals.Signal = @enumFromInt(num.*);
    var action = tsk.current.sighand.actions.get(signal);
    // for normal handlers offset should be 0 because restorer pops the signal number
    const regs_addr: u32 = signal_regs.useresp + 8;
    const saved_regs: *arch.Regs = @ptrFromInt(regs_addr);

    const siginfo_addr: u32 = regs_addr + @sizeOf(arch.Regs);
    const siginfo: *signals.Siginfo = @ptrFromInt(siginfo_addr);
    _ = siginfo;

    const ucontext_addr: u32 = siginfo_addr + @sizeOf(signals.Siginfo);
    const ucontext: *signals.Ucontext = @ptrFromInt(ucontext_addr);

    signal_regs.* = saved_regs.*;
    tsk.current.sigmask._bits[0] = ucontext.mask._bits[0];
    tsk.current.sigmask._bits[1] = ucontext.mask._bits[1];
    action.mask.sigDelSet(signal);
    tsk.current.sighand.actions.set(signal, action);
    if (saved_regs.eax >= 0) { // ERESTARTSYS
        return @intCast(saved_regs.eax);
    }
    return krn.errors.fromErrno(saved_regs.eax);
}

pub fn rt_sigreturn() !u32 {
    const signal_regs: *arch.Regs = @ptrFromInt(arch.gdt.tss.esp0 - @sizeOf(arch.Regs));
    const num: *u32 = @ptrFromInt(signal_regs.useresp);
    const signal: signals.Signal = @enumFromInt(num.*);
    var action = tsk.current.sighand.actions.get(signal);
    // for normal handlers offset should be 0 because restorer pops the signal number
    const regs_addr: u32 = signal_regs.useresp + 12;
    const saved_regs: *arch.Regs = @ptrFromInt(regs_addr);

    const siginfo_addr: u32 = regs_addr + @sizeOf(arch.Regs);
    const siginfo: *signals.Siginfo = @ptrFromInt(siginfo_addr);
    _ = siginfo;

    const ucontext_addr: u32 = siginfo_addr + @sizeOf(signals.Siginfo);
    const ucontext: *signals.Ucontext = @ptrFromInt(ucontext_addr);

    signal_regs.* = saved_regs.*;
    tsk.current.sigmask._bits[0] = ucontext.mask._bits[0];
    tsk.current.sigmask._bits[1] = ucontext.mask._bits[1];
    action.mask.sigDelSet(signal);
    tsk.current.sighand.actions.set(signal, action);
    if (saved_regs.eax >= 0)
        return @intCast(saved_regs.eax);
    return krn.errors.fromErrno(saved_regs.eax);
}

const SIG_BLOCK  : i32 = 0;	// for blocking signals
const SIG_UNBLOCK: i32 = 1;	// for unblocking signals
const SIG_SETMASK: i32 = 2;     // for setting the signal mask

pub fn rt_sigprocmask(
    how: i32,
    set: ?*signals.sigset_t,
    oset: ?*signals.sigset_t,
    sigsetsize: usize,
) !u32 {
    if (sigsetsize != @sizeOf(signals.sigset_t))
        return errors.EINVAL;
    return try sigprocmask(how, set, oset);
}

pub fn sigprocmask(
    how: i32,
    set: ?*signals.sigset_t,
    oset: ?*signals.sigset_t,
) !u32 {
    var oldset: u32 = 0;
    var newset: u32 = 0;
    var new_blocked: signals.sigset_t = signals.sigset_t.init();
    oldset = tsk.current.sigmask._bits[0];
    if (set) |_set| {
        newset = _set._bits[0];
        new_blocked = tsk.current.sigmask;
        switch (how) {
            SIG_BLOCK => {
                new_blocked._bits[0] |= newset;
            },
            SIG_UNBLOCK => {
                new_blocked._bits[0] &= ~newset;
            },
            SIG_SETMASK => {
                new_blocked._bits[0] = newset;
            },
            else => {
                return errors.EINVAL;
            }
        }
        new_blocked.sigDelSet(signals.Signal.SIGKILL);
        new_blocked.sigDelSet(signals.Signal.SIGSTOP);
        tsk.current.sigmask = new_blocked;
    }
    if (oset) |_oset| {
        _oset._bits[0] = oldset;
    }
    return 0;
}

pub fn rt_sigpending(
    uset: *signals.sigset_t,
    sigsetsize: usize,
) !u32 {
    if (sigsetsize != @sizeOf(signals.sigset_t))
        return errors.EINVAL;
    return sigpending(uset);
}

pub fn sigpending(uset: ?*signals.sigset_t) u32 {
    var set = signals.sigset_t.init();
    for (1..32) |idx| {
        if (tsk.current.sighand.pending.isSet(idx)) {
            set.sigAddSet(@enumFromInt(idx));
        }
    }
    if (uset) |_uset| {
        _uset.* = set;
    }
    return 0;
}

pub fn rt_sigsuspend(_mask: ?*signals.sigset_t) !u32 {
    const state = arch.Regs.state();
    const mask = _mask orelse
        return errors.EFAULT;
    krn.logger.INFO("sigsuspend mask {b:0>32}", .{mask._bits[0]});
    
    var uctx = signals.Ucontext{};
    uctx.mask = krn.task.current.sigmask;

    krn.task.current.sigmask = mask.*;

    if (krn.task.current.sighand.hasPending()) {
        state.eax = krn.errors.toErrno(errors.EINTR);
        _ = signals.processSignals(state, &uctx);
        return errors.EINTR;
    }

    krn.task.current.state = .INTERRUPTIBLE_SLEEP;
    krn.sched.reschedule();

    state.eax = krn.errors.toErrno(errors.EINTR);
    _ = signals.processSignals(state, &uctx);

    return errors.EINTR;
}

pub fn rt_sigtimedwait(
    set: ?*const signals.sigset_t,
    info: ?*signals.Siginfo,
    timeout: ?*const krn.kernel_timespec,
    sigsetsize: usize,
) !u32 {
    krn.logger.WARN(
        \\ rt_sigtimedwait:
        \\   set:        0x{x:0>8}
        \\   info:       0x{x:0>8}
        \\   timeout:    0x{x:0>8}
        \\   sigsetsize: {d}
        \\
        , .{
            @intFromPtr(set),
            @intFromPtr(info),
            @intFromPtr(timeout),
            sigsetsize,
        }
    );

    if (sigsetsize != @sizeOf(signals.sigset_t))
        return errors.EINVAL;

    const wait_set = set
        orelse return errors.EFAULT;

    var timeout_ms: ?u32 = null;
    if (timeout) |ts| {
        if (!ts.isValid())
            return errors.EINVAL;
        const sec_ms: u32 = @intCast(ts.tv_sec * 1000);
        const nsec_ms: u32 = @intCast(@divTrunc(ts.tv_nsec, 1_000_000));
        timeout_ms = sec_ms + nsec_ms;
    }

    const start_time = krn.currentMs();

    while (true) {
        for (1..32) |sig| {
            if (tsk.current.sighand.pending.isSet(sig)) {
                const signal: signals.Signal = @enumFromInt(sig);
                if (wait_set.sigIsSet(signal)) {
                    tsk.current.sighand.pending.unset(sig);
                    if (info) |i| {
                        i.signo = @intCast(sig);
                        i.errno = 0;
                        i.code = 0;
                        @memset(&i.fields.pad, 0);
                    }
                    return @intCast(sig);
                }
            }
        }

        if (timeout_ms) |ms| {
            if (ms == 0) {
                return errors.EAGAIN;
            }

            const elapsed = krn.currentMs() -| start_time;
            if (elapsed >= ms) {
                return errors.EAGAIN;
            }

            tsk.current.wakeup_time = start_time + ms;
        } else {
            tsk.current.wakeup_time = 0;
        }

        tsk.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
    }
}

/// Minimum signal stack size
pub const MINSIGSTKSZ: usize = 2048;
/// Default signal stack size
pub const SIGSTKSZ: usize = 8192;

/// Signal stack flags
pub const SS_ONSTACK: i32 = 1;
pub const SS_DISABLE: i32 = 2;

pub const StackT = extern struct {
    ss_sp: ?*anyopaque = null,
    ss_flags: i32 = SS_DISABLE,
    ss_size: usize = 0,
};

pub fn sigaltstack(
    ss: ?*StackT,
    old_ss: ?*StackT
) !u32 {
    _ = ss;
    _ = old_ss;
    return errors.EINVAL;
}
