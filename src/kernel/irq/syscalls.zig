const arch = @import("arch");
const tsk = @import("../sched/task.zig");
const krn = @import("../main.zig");
const registerHandler = @import("./manage.zig").registerHandler;
const systable = @import("../syscalls/table.zig");

pub fn syscallsManager(state: *arch.Regs) void {
    tsk.current.regs = state.*;
    asm volatile ("sti;");
    defer asm volatile ("cli;");
    if (state.eax < 0) {
        state.eax = -1;
        return;
    }
    const sys: systable.Syscall = @enumFromInt(state.eax);
    krn.logger.INFO("[PID {d:<2}]: {d:>4} {s}", .{
        tsk.current.pid,
        state.eax,
        @tagName(sys)
    });
    if (systable.SyscallTable.get(sys)) |hndlr| {
        state.eax = hndlr(
            state,
            state.ebx,
            state.ecx,
            state.edx,
            state.esi,
            state.edi,
            state.ebp,
        );
    }
}

pub fn initSyscalls() void {
    registerHandler(
        arch.SYSCALL_INTERRUPT - arch.CPU_EXCEPTION_COUNT,
        &syscallsManager
    );
}
