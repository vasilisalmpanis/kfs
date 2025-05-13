const tsk = @import("../sched/task.zig");
const signals = @import("../sched/signals.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const krn = @import("../main.zig");

pub fn sigaction(_: *arch.Regs, sig: u32, act: ?*signals.Sigaction, oact: ?*signals.Sigaction) i32 {
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

pub fn sigreturn(state: *arch.Regs) i32 {
    const num: *u32 = @ptrFromInt(state.useresp);
    const signal: signals.Signal = @enumFromInt(num.*);
    var action = tsk.current.sighand.actions.get(signal);
    var regs_offset: u32 = 4;
    if (action.flags & signals.SA_SIGINFO != 0) {
        regs_offset += 8;
    }
    const saved_regs: *arch.Regs = @ptrFromInt(state.useresp + regs_offset);
    state.* = saved_regs.*;
    action.mask.sigDelSet(signal);
    tsk.current.sighand.actions.set(signal, action);
    return 0;
}

const SIG_BLOCK  : i32 = 1;	// for blocking signals
const SIG_UNBLOCK: i32 = 2;	// for unblocking signals
const SIG_SETMASK: i32 = 3;     // for setting the signal mask

pub fn rt_sigprocmask(
    state: *arch.Regs,
    how: i32,
    set: ?*signals.sigset_t,
    oset: ?*signals.sigset_t,
    sigsetsize: usize,
) i32 {
    if (sigsetsize != @sizeOf(signals.sigset_t))
        return -errors.EINVAL;
    return sigprocmask(state, how, set, oset);
}

pub fn sigprocmask(
    _: *arch.Regs,
    how: i32,
    set: ?*signals.sigset_t,
    oset: ?*signals.sigset_t,
) i32 {
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
                return -errors.EINVAL;
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
    state: *arch.Regs,
    uset: *signals.sigset_t,
    sigsetsize: usize,
) i32 {
    if (sigsetsize != @sizeOf(signals.sigset_t))
        return -errors.EINVAL;
    return sigpending(state, uset);
}

pub fn sigpending(
    _: *arch.Regs,
    uset: ?*signals.sigset_t,
) i32 {
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
