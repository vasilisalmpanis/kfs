const tsk = @import("./task.zig");
const krn = @import("../main.zig");
const std = @import("std");
const arch = @import("arch");
pub const SIG_COUNT: u8 = 32;

const SigHandler = fn (signum: u8) void;

const sigDFL: ?*SigHandler = @ptrFromInt(0);
const sigIGN: ?*SigHandler = @ptrFromInt(1);
const sigERR: ?*SigHandler = @ptrFromInt(-1);

const Signal = enum(u8) {
    EMPTY = 0,      // Default action      comment                     posix       0
    SIGHUP = 1,     // Terminate   Hang up controlling terminal or      Yes        1
    SIGINT,         // Terminate   Interrupt from keyboard, Control-C   Yes        2
    SIGQUIT,        // Dump        Quit from keyboard, Control-\        Yes        3
    SIGILL,         // Dump        Illegal instruction                  Yes        4
    SIGTRAP,        // Dump        Breakpoint for debugging             No         5
    SIGABRT,        // Dump        Abnormal termination                 Yes        6
    SIGIOT,         // Dump        Equivalent to SIGABRT                No         7
    SIGBUS,         // Dump        Bus error                            No         8
    SIGFPE,         // Dump        Floating-point exception           .EMPTY  Yes  9
    SIGKILL,        // Terminate   Forced-process termination           Yes        10
    SIGUSR1,        // Terminate   Available to processes               Yes        11
    SIGSEGV,        // Dump        Invalid memory reference             Yes        12
    SIGUSR2,        // Terminate   Available to processes               Yes        13
    SIGPIPE,        // Terminate   Write to pipe with no readers        Yes        14
    SIGALRM,        // Terminate   Real-timer clock                     Yes        15
    SIGTERM,        // Terminate   Process termination                  Yes        16
    SIGSTKFLT,      // Terminate   Coprocessor stack error              No         17
    SIGCHLD,        // Ignore      Child process stopped or terminated  Yes        18
    SIGCONT,        // Continue    Resume execution, if stopped         Yes        19
    SIGSTOP,        // Stop        Stop process execution, Ctrl-Z       Yes        20
    SIGTSTP,        // Stop        Stop process issued from tty         Yes        21
    SIGTTIN,        // Stop        Background process requires input    Yes        22
    SIGTTOU,        // Stop        Background process requires output   Yes        23
    SIGURG,         // Ignore      Urgent condition on socket           No         24
    SIGXCPU,        // Dump        CPU time limit exceeded              No         25
    SIGXFSZ,        // Dump        File size limit exceeded             No         26
    SIGVTALRM,      // Terminate   Virtual timer clock                  No         27
    SIGPROF,        // Terminate   Profile timer clock                  No         28
    SIGWINCH,       // Ignore      Window resizing                      No         29
    SIGIO,          // Terminate   I/O now possible                     No         30
    SIGPOLL,        // Terminate   Equivalent to SIGIO                  No         31
    SIGPWR,         // Terminate   Power supply failure                 No         32
    SIGSYS,         // Dump        Bad system call                      No         33
    SIGUNUSED,      // Dump        Equivalent to SIGSYS                 No         34
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

fn sigIgn(_: u8) void {
    return;
}

pub const SigAction = struct {
    processing: bool = false,
    pending: std.StaticBitSet(32) = std.StaticBitSet(32).initEmpty(),
    sig_handlers: std.EnumArray(Signal, ?*const SigHandler) =
        std.EnumArray(Signal, ?*const SigHandler).init(.{
            .EMPTY      = sigDFL,
            .SIGHUP     = sigHup,
            .SIGINT     = sigDFL,
            .SIGQUIT    = sigDFL,
            .SIGILL     = sigDFL,
            .SIGTRAP    = sigDFL,
            .SIGABRT    = sigDFL,
            .SIGIOT     = sigDFL,
            .SIGBUS     = sigDFL,
            .SIGFPE     = sigDFL,
            .SIGKILL    = sigDFL,
            .SIGUSR1    = sigDFL,
            .SIGSEGV    = sigDFL,
            .SIGUSR2    = sigDFL,
            .SIGPIPE    = sigDFL,
            .SIGALRM    = sigDFL,
            .SIGTERM    = sigDFL,
            .SIGSTKFLT  = sigDFL,
            .SIGCHLD    = sigIgn,
            .SIGCONT    = sigDFL,
            .SIGSTOP    = sigDFL,
            .SIGTSTP    = sigDFL,
            .SIGTTIN    = sigDFL,
            .SIGTTOU    = sigDFL,
            .SIGURG     = sigDFL,
            .SIGXCPU    = sigDFL,
            .SIGXFSZ    = sigDFL,
            .SIGVTALRM  = sigDFL,
            .SIGPROF    = sigDFL,
            .SIGWINCH   = sigDFL,
            .SIGIO      = sigDFL,
            .SIGPOLL    = sigDFL,
            .SIGPWR     = sigDFL,
            .SIGSYS     = sigDFL,
            .SIGUNUSED  = sigDFL,
        }),
    
    pub fn init() SigAction {
        return SigAction{};
    }

    pub fn deliverSignals(self: *SigAction) bool {
        var it = self.pending.iterator(.{});
        while (it.next()) |i| {
            self.pending.toggle(i);
            const signal: Signal = @enumFromInt(i);
            if (self.sig_handlers.get(signal)) |handler| {
                handler(@intCast(i));
                if (SignalTerminated.get(signal) orelse false)
                    return true;
            } else {
                return false;
            }
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
    if (task.sigaction.isReady()) {
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
