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
    var regs_offset: u32 = 0;
    if (action.flags & signals.SA_SIGINFO != 0) {
        regs_offset += 8;
    }
    const saved_regs: *arch.Regs = @ptrFromInt(signal_regs.useresp + regs_offset);
    signal_regs.* = saved_regs.*;
    action.mask.sigDelSet(signal);
    tsk.current.sighand.actions.set(signal, action);
    return 0;
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

pub fn rt_sigsuspend(mask: u32) !u32 {
    // krn.logger.INFO("Sigsuspend mask {b}\n", .{mask});
    // const old: u32 = krn.task.current.sigmask._bits[0];
    _ = mask;
    krn.task.current.sigmask.sigDelSet(signals.Signal.SIGCHLD);
    // krn.task.current.state = .INTERRUPTIBLE_SLEEP;
    krn.sched.reschedule();
    // krn.task.current.sigmask._bits[0] = old;
    return errors.EINTR;
}
