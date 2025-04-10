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
    krn.logger.WARN("Default signal handler\n", .{});
}

pub fn signalWrapper() void {
    asm volatile (arch.idt.push_regs);
    var stack: u32 = 1;
    stack +=1;
    if (tsk.current.sigaction.deliverSignals()) {
        while (true) {}
    }
    asm volatile (arch.idt.pop_regs);
    return;
}

fn sigHup(_: u8) void {
    // Terminating.
    tsk.tasks_mutex.lock();
    tsk.current.state = .STOPPED;
    tsk.current.list.del();
    if (tsk.stopped_tasks == null) {
        tsk.stopped_tasks = &tsk.current.list;
        tsk.stopped_tasks.?.setup();
    } else {
        tsk.stopped_tasks.?.addTail(&tsk.current.list);
    }
    tsk.tasks_mutex.unlock();
}

pub const SigAction = struct {
    processing: bool = false,
    pending: std.StaticBitSet(32) = std.StaticBitSet(32).initEmpty(),
    sig_handlers: std.EnumArray(Signal, *const SigHandler) =
        std.EnumArray(Signal, *const SigHandler).init(.{
            .EMPTY      = &sigHandler,
            .SIGHUP     = &sigHup,
            .SIGINT     = &sigHandler,
            .SIGQUIT    = &sigHandler,
            .SIGILL     = &sigHandler,
            .SIGTRAP    = &sigHandler,
            .SIGABRT    = &sigHandler,
            .SIGIOT     = &sigHandler,
            .SIGBUS     = &sigHandler,
            .SIGFPE     = &sigHandler,
            .SIGKILL    = &sigHandler,
            .SIGUSR1    = &sigHandler,
            .SIGSEGV    = &sigHandler,
            .SIGUSR2    = &sigHandler,
            .SIGPIPE    = &sigHandler,
            .SIGALRM    = &sigHandler,
            .SIGTERM    = &sigHandler,
            .SIGSTKFLT  = &sigHandler,
            .SIGCHLD    = &sigHandler,
            .SIGCONT    = &sigHandler,
            .SIGSTOP    = &sigHandler,
            .SIGTSTP    = &sigHandler,
            .SIGTTIN    = &sigHandler,
            .SIGTTOU    = &sigHandler,
            .SIGURG     = &sigHandler,
            .SIGXCPU    = &sigHandler,
            .SIGXFSZ    = &sigHandler,
            .SIGVTALRM  = &sigHandler,
            .SIGPROF    = &sigHandler,
            .SIGWINCH   = &sigHandler,
            .SIGIO      = &sigHandler,
            .SIGPOLL    = &sigHandler,
            .SIGPWR     = &sigHandler,
            .SIGSYS     = &sigHandler,
            .SIGUNUSED  = &sigHandler,
        }),
    
    pub fn init() SigAction {
        return SigAction{};
    }

    pub fn deliverSignals(self: *SigAction) bool {
        var it = self.pending.iterator(.{});
        while (it.next()) |i| {
            self.pending.toggle(i);
            const signal: Signal = @enumFromInt(i);
            self.sig_handlers.get(signal)(@intCast(i));
                if (SignalTerminated.get(signal) orelse false)
                    return true;
        }
        self.processing = false;
        return false;
    }

    pub fn setSignal(self: *SigAction, signal: Signal) void {
        self.pending.set(@intFromEnum(signal));
    }

    pub fn isReady(self: *SigAction) bool {
        if (self.processing)
            return false;
        if (self.pending.count() != 0) {
            self.processing = true;
            return true;
        }
        return false;
    }
};

pub fn processSignals(task: *tsk.Task) void {
    if (tsk.current.sigaction.isReady()) {
        const regs: *arch.Regs = @ptrFromInt(task.regs.esp);
        const eip: u32 = regs.eip;

        regs.eip = @intFromPtr(&signalWrapper);

        const kernelContextSize = @sizeOf(arch.Regs) - 8;
        const returnAddrSize: u32 = 4;

        const new: [*]u32 = @ptrFromInt(task.regs.esp - returnAddrSize);
        const old: [*]u32 = @ptrFromInt(task.regs.esp);
        std.mem.copyForwards(
            u32,
            new[0..kernelContextSize/4],
            old[0..kernelContextSize/4],
        );

        task.regs.esp -= returnAddrSize;

        const original_return: *u32 = @ptrFromInt(task.regs.esp + kernelContextSize);
        original_return.* = eip;
    }
}
