const arch = @import("arch");
const init = @import("../syscalls/init.zig");
const tsk = @import("../sched/task.zig");
const krn = @import("../main.zig");
const registerHandler = @import("./manage.zig").registerHandler;

pub var syscalls: [arch.IDT_MAX_DESCRIPTORS] ?* const anyopaque = .{null} ** arch.IDT_MAX_DESCRIPTORS;

const SyscallHandler = fn (
    state: *arch.Regs,
    a1: u32,
    a2: u32,
    a3: u32,
    a4: u32,
    a5: u32,
) i32;

pub fn syscallsManager(state: *arch.Regs) void {
    tsk.current.regs = state.*;
    asm volatile ("sti;");
    defer asm volatile ("cli;");
    if (state.eax < 0 or state.eax >= arch.IDT_MAX_DESCRIPTORS) {
        state.eax = -1;
        return;
    }
    krn.logger.INFO("syscall {d}", .{state.eax});
    if (syscalls[@intCast(state.eax)]) |handler| {
        const hnd: *const SyscallHandler = @ptrCast(handler);
        state.eax = hnd(
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
    init.init();
}

pub fn registerSyscall(num: u32, handler: * const anyopaque) void {
    if (num >= arch.IDT_MAX_DESCRIPTORS)
        @panic("Wrong syscall number, should be < arch.IDT_MAX_DESCRIPTORS!");
    syscalls[num] = handler;
}


// 0     read         read(2)        sys_read
// 1     write        write(2)       sys_write
// 2     open         open(2)        sys_open
// 3     close        close(2)       sys_close
// 4     stat         stat(2)        sys_newstat
// 9     mmap         mmap(2)        sys_ksys_mmap_pgoff
// 10    mprotect     mprotect(2)    sys_mprotect
// 11    munmap       munmap(2)      sys_munmap
// 56    clone        clone(2)       sys_clone
// 57    fork         fork(2)        sys_fork
// 58    vfork        vfork(2)       sys_vfork
// 59    execve       execve(2)      sys_execve
// 60    exit         exit(2)        sys_exit
// 61    wait4        wait4(2)       sys_wait4
// 62    kill         kill(2)        sys_kill
