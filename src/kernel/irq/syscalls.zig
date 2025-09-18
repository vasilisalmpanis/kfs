const arch = @import("arch");
const tsk = @import("../sched/task.zig");
const krn = @import("../main.zig");
const registerHandler = @import("./manage.zig").registerHandler;
const systable = @import("../syscalls/table.zig");
const errors = @import("../syscalls/error-codes.zig");

pub fn syscallsManager(state: *arch.Regs) void {
    tsk.current.regs = state.*;
    asm volatile ("sti;");
    defer asm volatile ("cli;");
    if (state.eax < 0) {
        state.eax = -1;
        return;
    }
    const sys: systable.Syscall = @enumFromInt(state.eax);
    if (sys != .SYS_write
        and sys != .SYS_read
        and sys != .SYS_writev
        and sys != .SYS_pwritev
        and sys != .SYS_poll
    ) {
        krn.logger.INFO("[PID {d:<2}]: {d:>4} {t}", .{
            tsk.current.pid,
            state.eax,
            sys
        });
    }
    if (systable.SyscallTable.get(sys)) |hndlr| {
        const result: u32 = hndlr(
            state.ebx,
            state.ecx,
            state.edx,
            state.esi,
            state.edi,
            state.ebp,
        ) catch |err| {
            state.eax = errors.toErrno(err);
            return ;
        };
        state.eax = @bitCast(result);
    }
}

pub fn initSyscalls() void {
    registerHandler(
        arch.SYSCALL_INTERRUPT - arch.CPU_EXCEPTION_COUNT,
        &syscallsManager
    );
}
