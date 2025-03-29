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

fn sigHandler(signum: u8) void {
    _ = signum;
}

pub const SigAction = struct {
    sig_handlers:   [SIG_COUNT]*const SigHandler = undefined,
    
    pub fn init() SigAction {
        var sigaction = SigAction{};
        for (0..SIG_COUNT) |idx| {
            sigaction.sig_handlers[idx] = &sigHandler;
        }
        return sigaction;
    }
};

pub fn setSignal(pending: u32, signal: Signal) u32 {
    const s: u8 = @intFromEnum(signal);
    const mask: u32 = @as(u32, 1) << @as(u5, @truncate(s));
    return pending | mask;
}
