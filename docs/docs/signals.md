# Signals

A signal is an asynchronous notification sent to a process or to a specific thread 
within the same process to notify it of an event. Common uses of signals are to 
interrupt, suspend, terminate or kill a process.

In **KFS** signals cannot be queued but user-provided signal handlers can run nested. The amount
of handlers that can run nested is not limited by the kernel. The programmer is responsible for
using good coding practices and common sense.

**KFS** implements the following flags for sigaction

* **SA_NODEFER**   Do not add the signal to the thread's signal mask while the
                handler is executing, unless the signal is specified in
                act.sa_mask
* **SA_RESETHAND**   Resets the handler of the signal to default when execution of that handler starts.

* **SA_SIGINFO**   sa_sigaction specifies the signal-handling function for signum.
                    This function receives three arguments,

## Execution

Everytime that there is a transition from kernel-mode to user-mode the kernel checks
if there is an unblocked signal, that the process has established a custom handler for.
If there is such a pending signal the following steps take place.

1. The kernel clears the bit of the signal from the pending signals.
    - Various information regarding the signal context are saved into a frame that is created on the stack.
    - The register context to restore the task once the handler is finished.
    - The signal number.

    - Any signals specified in act->sa_mask when registering
                   the handler with sigaction) are added to the
                   task's signal mask.  The signal being delivered is
                   also added to the signal mask, unless SA_NODEFER was
                   specified when registering the handler. These signals
                   are thus blocked while the handler executes.

2. The kernel sets the program counter for the task to point to the first
instruction of the signal handler function and set the return address for 
this handler to point to a user-space piece of code known as the signal 
trampoline (calls sigreturn).

3. The kernel passes back control to user-space, and execution starts
at the beggining of the signal handler function.

4. When the handler returns, the signal trampoline code is executed.

5. The signal trampoline calls sigreturn, which uses the information stored
on the stack to restore the task to its state before the signal handler was 
called. The tasks signal mask is restored during this procedure. Upon
completion of sigreturn, the kernel transfers control back to user space, 
and the task recommences execution at the point where it was interrupted 
by the signal handler.

## Standard Signals

**KFS** supports the standard signals listed below:

|   Signal    |   Value   |   Action   |
|:-----------:|:---------:|:----------:|
|   SIGHUP    |     1     |    Term    |
|   SIGINT    |     2     |    Term    |
|   SIGQUIT   |     3     |    Core    |
|   SIGILL    |     4     |    Core    |
|   SIGTRAP   |     5     |    Core    |
|   SIGABRT   |     6     |    Core    |
|   SIGIOT    |     6     |    Core    |
|   SIGBUS    |     7     |    Core    |
|   SIGFPE    |     8     |    Core    |
|   SIGKILL   |     9     |    Term    |
|   SIGUSR1   |    10     |    Term    |
|   SIGSEGV   |    11     |    Core    |
|   SIGUSR2   |    12     |    Term    |
|   SIGPIPE   |    13     |    Term    |
|   SIGALRM   |    14     |    Term    |
|   SIGTERM   |    15     |    Term    |
|  SIGSTKFLT  |    16     |    Term    |
|   SIGCHLD   |    17     |    Ign     |
|   SIGCONT   |    18     |    Cont    |
|   SIGSTOP   |    19     |    Stop    |
|   SIGTSTP   |    20     |    Stop    |
|   SIGTTIN   |    21     |    Stop    |
|   SIGTTOU   |    22     |    Stop    |
|   SIGURG    |    23     |    Ign     |
|   SIGXCPU   |    24     |    Core    |
|   SIGXFSZ   |    25     |    Core    |
|  SIGVTALRM  |    26     |    Term    |
|   SIGPROF   |    27     |    Term    |
|   SIGWINCH  |    28     |    Ign     |
|    SIGIO    |    29     |    Term    |
|    SIGPWR   |    30     |    Term    |
|    SIGSYS   |    31     |    Core    |
|  SIGUNUSED  |    31     |    Core    |

## Queuing
If multiple standard signals are pending for a process, the order
       in which the signals are delivered is unspecified.

Standard signals do not queue.  If multiple instances of a
standard signal are generated while that signal is blocked, then
only one instance of the signal is marked as pending (and the
signal will be delivered just once when it is unblocked).

## Interruption of system calls
If a signal handler is invoked while a system call or library function call is blocked, then:

- the call fails with the error **EINTR**.  

Support for **SA_RESTART** is coming in the future.

## Syscalls
**KFS** supports the following signal-related syscalls.

- **sigaction**
- **rt_sigaction**
- **kill**
- **sigpending**
- **rt_sigpending**
- **sigprocmask**
- **rt_sigprocmask**
- **sigreturn**
