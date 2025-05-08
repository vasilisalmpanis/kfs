const tsk = @import("../sched/task.zig");
const signals = @import("../sched/signals.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const krn = @import("../main.zig");

pub fn sigaction(_: *arch.Regs, sig: u32, act: ?*signals.Sigaction, oact: ?*signals.Sigaction) i32 {
    krn.logger.INFO("sigaction {d} {any} {any}", .{sig, act, oact});
    tsk.current.sighand.actions.set(@enumFromInt(sig), act.?.*);
    return 0;
}

pub fn sigreturn(state: *arch.Regs) i32 {
    const signal: *u32 = @ptrFromInt(state.useresp);
    const saved_regs: *arch.Regs = @ptrFromInt(state.useresp + 4);
    state.* = saved_regs.*;
    var action = tsk.current.sighand.actions.get(@enumFromInt(signal.*));
    action.mask[0] &= ~signal.*;
    tsk.current.sighand.actions.set(@enumFromInt(signal.*), action);
    return 0;
 }
