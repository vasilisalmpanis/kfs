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
    tsk.current.sighand.actions.set(signal, act.?.*);
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
    action.sigDelSet(signal);
    tsk.current.sighand.actions.set(signal, action);
    return 0;
}

pub fn rt_sigprocmask(
    state: *arch.Regs,
    how: i32,
    set: *signals.sigset_t,
    oset: *signals.sigset_t,
    sigsetsize: usize,
) i32 {
    _ = state;
    _ = how;
    _ = set;
    _ = oset;
    _ = sigsetsize;
    return 0;
}

pub fn sigprocmask(
    state: *arch.Regs,
    how: i32,
    set: *signals.sigset_t,
    oset: *signals.sigset_t,
) i32 {
    _ = state;
    _ = how;
    _ = set;
    _ = oset;
    return 0;
}

pub fn rt_sigpending(
    state: *arch.Regs,
    set: *signals.sigset_t,
    sigsetsize: usize,
) i32 {
    _ = state;
    _ = set;
    _ = sigsetsize;
    return 0;
}

pub fn sigpending(
    state: *arch.Regs,
    set: *signals.sigset_t,
) i32 {
    _ = state;
    _ = set;

    var i: u32 = 0;
    while (true) {
        i +%= 1;
        if (i % 10000 == 0)
            krn.logger.WARN("sigpending...", .{});
    }
    return 0;
}
