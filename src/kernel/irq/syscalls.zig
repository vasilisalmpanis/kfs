const arch = @import("arch");
const tsk = @import("../sched/task.zig");
const krn = @import("../main.zig");
const registerHandler = @import("./manage.zig").registerHandler;
const systable = @import("../syscalls/table.zig");

pub fn syscallsManager(state: *arch.Regs) void {
    tsk.current.regs = state.*;
    asm volatile ("sti;");
    defer asm volatile ("cli;");
    if (state.eax < 0 or state.eax >= arch.IDT_MAX_DESCRIPTORS) {
        state.eax = -1;
        return;
    }
    krn.logger.INFO("[PID {d:<2}]: {d:>4} {s}", .{
        tsk.current.pid,
        state.eax,
        @tagName(@as(systable.Syscall, @enumFromInt(state.eax)))
    });
    if (systable.SyscallTable.get(@enumFromInt(state.eax))) |hndlr| {
        state.eax = hndlr(
            state,
            state.ebx,
            state.ecx,
            state.edx,
            state.esi,
            state.edi,
        );
    }
}

pub fn initSyscalls() void {
    registerHandler(
        arch.SYSCALL_INTERRUPT - arch.CPU_EXCEPTION_COUNT,
        &syscallsManager
    );
}
