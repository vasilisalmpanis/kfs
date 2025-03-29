const tsk = @import("./task.zig");
const krn = @import("../main.zig");
const std = @import("std");
const arch = @import("arch");
pub const SIG_COUNT: u8 = 32;

const SigHandler = fn (signum: u8) void;

const Signal = enum(u8) {
    EMPTY = 0,      // Default action      comment                     posix
    SIGHUP = 1,     // Terminate   Hang up controlling terminal or      Yes
    SIGINT,         // Terminate   Interrupt from keyboard, Control-C   Yes
    SIGQUIT,        // Dump        Quit from keyboard, Control-\        Yes
    SIGILL,         // Dump        Illegal instruction                  Yes
    SIGTRAP,        // Dump        Breakpoint for debugging             No
    SIGABRT,        // Dump        Abnormal termination                 Yes
    SIGIOT,         // Dump        Equivalent to SIGABRT                No
    SIGBUS,         // Dump        Bus error                            No
    SIGFPE,         // Dump        Floating-point exception           .EMPTY  Yes
    SIGKILL,        // Terminate   Forced-process termination           Yes
    SIGUSR1,        // Terminate   Available to processes               Yes
    SIGSEGV,        // Dump        Invalid memory reference             Yes
    SIGUSR2,        // Terminate   Available to processes               Yes
    SIGPIPE,        // Terminate   Write to pipe with no readers        Yes
    SIGALRM,        // Terminate   Real-timer clock                     Yes
    SIGTERM,        // Terminate   Process termination                  Yes
    SIGSTKFLT,      // Terminate   Coprocessor stack error              No
    SIGCHLD,        // Ignore      Child process stopped or terminated  Yes
    SIGCONT,        // Continue    Resume execution, if stopped         Yes
    SIGSTOP,        // Stop        Stop process execution, Ctrl-Z       Yes
    SIGTSTP,        // Stop        Stop process issued from tty         Yes
    SIGTTIN,        // Stop        Background process requires input    Yes
    SIGTTOU,        // Stop        Background process requires output   Yes
    SIGURG,         // Ignore      Urgent condition on socket           No
    SIGXCPU,        // Dump        CPU time limit exceeded              No
    SIGXFSZ,        // Dump        File size limit exceeded             No
    SIGVTALRM,      // Terminate   Virtual timer clock                  No
    SIGPROF,        // Terminate   Profile timer clock                  No
    SIGWINCH,       // Ignore      Window resizing                      No
    SIGIO,          // Terminate   I/O now possible                     No
    SIGPOLL,        // Terminate   Equivalent to SIGIO                  No
    SIGPWR,         // Terminate   Power supply failure                 No
    SIGSYS,         // Dump        Bad system call                      No
    SIGUNUSED,      // Dump        Equivalent to SIGSYS                 No
};

const SignalTerminated = std.EnumMap(Signal, bool).init(.{
    .EMPTY      = false,
    .SIGHUP     = true,
    .SIGINT     = true,
    .SIGQUIT    = false,
    .SIGILL     = false,
    .SIGTRAP    = false,
    .SIGABRT    = false,
    .SIGIOT     = false,
    .SIGBUS     = false,
    .SIGFPE     = false,
    .SIGKILL    = true,
    .SIGUSR1    = true,
    .SIGSEGV    = false,
    .SIGUSR2    = true,
    .SIGPIPE    = true,
    .SIGALRM     = true,
    .SIGTERM     = true,
    .SIGSTKFLT  = true,
    .SIGCHLD    = false,
    .SIGCONT    = false,
    .SIGSTOP    = false,
    .SIGTSTP    = false,
    .SIGTTIN    = false,
    .SIGTTOU    = false,
    .SIGURG     = false,
    .SIGXCPU    = false,
    .SIGXFSZ    = false,
    .SIGVTALRM  = true,
    .SIGPROF    = true,
    .SIGWINCH   = false,
    .SIGIO      = true,
    .SIGPOLL    = true,
    .SIGPWR     = true,
    .SIGSYS     = false,
    .SIGUNUSED  = false,
});
fn sigHandler(signum: u8) void {
    _ = signum;
    krn.logger.WARN("Hup\n", .{});
}

pub fn signalWrapper() void {
    asm volatile ("pop %ebp;");
    const stack: u32 = arch.cpu.getESP();
    const eip: u32 = tsk.current.sig_eip;
    // const pending = tsk.current.sig_pending;
    tsk.current.sig_pending = 0;
    asm volatile (arch.idt.push_regs);
    asm volatile(
        \\ xor %eax, %eax
        \\ xor %ebx, %ebx
        \\ xor %ecx, %ecx
    );
    // if (tsk.current.sigaction.deliverSignals(pending)) {
        // @import("./scheduler.zig").reschedule();
    // }
    // arch.io.outb(0x3F8, 'a');
    asm volatile (arch.idt.pop_regs);
    tsk.current.sig_eip = 0;
    asm volatile (
        \\ cli
        \\ push $0x10
        \\ push %[stack]
        \\ pushf
        \\ pop %ebx
        \\ or $0x200, %ebx
        \\ push %ebx
        \\ push $0x8
        \\ push %[eip]
        \\ iret
        :: [stack] "r" (stack), [eip] "r" (eip)
        :
    );
}

fn sigHup(_: u8) void {
    // Terminating.
    // tsk.current.state = .STOPPED;
    // tsk.current.list.del();
    // if (tsk.stopped_tasks == null) {
    //     tsk.stopped_tasks = &tsk.current.list;
    //     tsk.stopped_tasks.?.setup();
    // } else {
    //     tsk.stopped_tasks.?.addTail(&tsk.current.list);
    // }
    // tsk.tasks_mutex.unlock();
    krn.logger.WARN("Hup\n", .{});
}

pub const SigAction = struct {
    sig_handlers:   [SIG_COUNT]*const SigHandler = undefined,
    
    pub fn init() SigAction {
        var sigaction = SigAction{};
        for (0..SIG_COUNT) |idx| {
            sigaction.sig_handlers[idx] = &sigHandler;
        }
        sigaction.sig_handlers[1] = &sigHup;
        return sigaction;
    }

    pub fn deliverSignals(self: *SigAction, pending: u32) bool {
        var temp: u32 = pending;
        for(0..32) |i| {
            temp = pending >> @as(u5, @truncate(i));
            if (temp & 0x1 > 0) {
                self.sig_handlers[i](@intCast(i));
                if (SignalTerminated.get(@enumFromInt(i)) orelse false)
                    return true;
            }
        }
        return false;
    }
};

pub fn setSignal(pending: u32, signal: Signal) u32 {
    const s: u8 = @intFromEnum(signal);
    const mask: u32 = @as(u32, 1) << @as(u5, @truncate(s));
    return pending | mask;
}
