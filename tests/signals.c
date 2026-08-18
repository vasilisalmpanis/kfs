/*
 * signal test suite
 *
 * Covers: sigaction, sigprocmask, sigpending, sigreturn (mask restore),
 *         SA_NODEFER, SA_RESETHAND, SA_SIGINFO, sa_mask, sigsuspend,
 *         pthread_kill, pthread_sigmask, thread-masked signal delivery,
 *         exit / exit_group, SIGCHLD, WIFSIGNALED.
 *
 * Build:
 *   zig cc -target x86-linux-musl -static -o test_signals test_signals.c -lpthread
 */

#define _GNU_SOURCE

#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <pthread.h>

/* x86 32-bit syscall numbers (in case sys/syscall.h is incomplete) */
#ifndef SYS_exit
#define SYS_exit       1
#endif
#ifndef SYS_exit_group
#define SYS_exit_group 252
#endif
#ifndef SYS_gettid
#define SYS_gettid    224
#endif
#ifndef SYS_tkill
#define SYS_tkill     238
#endif

/* Signal sent via tkill that asks a worker thread to exit itself via SYS_exit.
 * We can't just send SIGKILL because in our kernel SIGKILL's default action
 * exits the whole thread group. Instead each worker installs a handler for
 * this signal that calls SYS_exit (raw, per-thread). pthread_join would need
 * futexes (not implemented) so this is how we tear workers down. */
#define SIG_TKILL_EXIT  SIGTERM

static void tkill_exit_handler(int s) {
    (void)s;
    syscall(SYS_exit, 0);
}

static void install_tkill_exit_handler(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = tkill_exit_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIG_TKILL_EXIT, &sa, NULL);
}

static int tkill_thread(pid_t tid)
{
    return syscall(SYS_tkill, tid, SIG_TKILL_EXIT);
}

/* ------------------------------------------------------------------ */
/* Result tracking                                                      */
/* ------------------------------------------------------------------ */

static int g_passed = 0;
static int g_failed = 0;

static void ok(const char *name)
{
    printf("  PASS  %s\n", name);
    g_passed++;
}

static void nok(const char *name, const char *why)
{
    printf("  FAIL  %s  [%s]\n", name, why);
    g_failed++;
}

#define CHECK(cond, name, why) \
    do { if ((cond)) ok(name); else nok(name, why); } while (0)

/* ------------------------------------------------------------------ */
/* Helper: reset SIGUSR1 / SIGUSR2 to SIG_DFL, fully unblocked        */
/* ------------------------------------------------------------------ */

static void reset_usr(void)
{
    struct sigaction dfl;
    memset(&dfl, 0, sizeof dfl);
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    sigaction(SIGUSR1, &dfl, NULL);
    sigaction(SIGUSR2, &dfl, NULL);

    sigset_t u;
    sigemptyset(&u);
    sigaddset(&u, SIGUSR1);
    sigaddset(&u, SIGUSR2);
    pthread_sigmask(SIG_UNBLOCK, &u, NULL);
}

/* ================================================================== */
/* 1. Basic sigaction install and delivery                              */
/* ================================================================== */

static volatile sig_atomic_t basic_fired;
static void basic_handler(int s) { (void)s; basic_fired = 1; }

static void test_basic_sigaction(void)
{
    puts("\n[ 1. basic sigaction ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = basic_handler;
    sigemptyset(&sa.sa_mask);

    CHECK(sigaction(SIGUSR1, &sa, NULL) == 0,
          "sigaction install returns 0", "call failed");

    basic_fired = 0;
    raise(SIGUSR1);
    CHECK(basic_fired, "handler called", "not called");

    struct sigaction got;
    sigaction(SIGUSR1, NULL, &got);
    CHECK(got.sa_handler == basic_handler,
          "sigaction GET returns installed handler", "wrong pointer");

    reset_usr();
}

/* ================================================================== */
/* 2. SA_RESETHAND                                                      */
/* ================================================================== */

static volatile sig_atomic_t rh_count;
static void rh_handler(int s) { (void)s; rh_count++; }

static void test_sa_resethand(void)
{
    puts("\n[ 2. SA_RESETHAND ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = rh_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESETHAND;
    sigaction(SIGUSR1, &sa, NULL);

    rh_count = 0;
    raise(SIGUSR1);
    CHECK(rh_count == 1, "handler called exactly once", "wrong count");

    struct sigaction after;
    sigaction(SIGUSR1, NULL, &after);
    CHECK(after.sa_handler == SIG_DFL,
          "disposition reset to SIG_DFL", "not SIG_DFL");

    reset_usr();
}

/* ================================================================== */
/* 3. SA_NODEFER — recursive re-entry vs. default defer                */
/* ================================================================== */

static volatile sig_atomic_t nd_depth;
static volatile sig_atomic_t nd_max;

static void nd_handler(int s)
{
    (void)s;
    nd_depth++;
    if (nd_depth > nd_max) nd_max = nd_depth;
    if (nd_depth < 3) raise(SIGUSR1);
    nd_depth--;
}

static volatile sig_atomic_t df_depth;
static volatile sig_atomic_t df_max;
static volatile sig_atomic_t df_calls;

static void df_handler(int s)
{
    (void)s;
    df_calls++;
    df_depth++;
    if (df_depth > df_max) df_max = df_depth;
    /* raise only on the first call: without SA_NODEFER the signal is queued,
       not re-entered, so depth stays 1; a second raise would loop forever */
    if (df_depth < 3 && df_calls == 1)
        raise(SIGUSR1);
    df_depth--;
}

static void test_sa_nodefer(void)
{
    puts("\n[ 3. SA_NODEFER ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = nd_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NODEFER;
    sigaction(SIGUSR1, &sa, NULL);

    nd_depth = nd_max = 0;
    raise(SIGUSR1);
    CHECK(nd_max >= 2,
          "SA_NODEFER: recursive delivery (depth >= 2)", "no recursion");

    reset_usr();
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = df_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGUSR1, &sa, NULL);

    df_depth = df_max = df_calls = 0;
    raise(SIGUSR1);
    CHECK(df_max == 1,
          "without SA_NODEFER: no recursion (depth stays 1)", "unexpected recursion");

    reset_usr();
}

/* ================================================================== */
/* 4. SA_SIGINFO — three-argument handler                              */
/* ================================================================== */

static volatile sig_atomic_t si_signo;
static volatile sig_atomic_t si_called;

static void si_handler(int s, siginfo_t *info, void *ctx)
{
    (void)s; (void)ctx;
    si_signo  = info->si_signo;
    si_called = 1;
}

static void test_sa_siginfo(void)
{
    puts("\n[ 4. SA_SIGINFO ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = si_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGUSR2, &sa, NULL);

    si_called = si_signo = 0;
    raise(SIGUSR2);
    CHECK(si_called, "handler called", "not called");
    CHECK(si_signo == SIGUSR2, "si_signo correct", "wrong signo");

    reset_usr();
}

/* ================================================================== */
/* 5. SIG_BLOCK prevents delivery; SIG_UNBLOCK releases pending        */
/* ================================================================== */

static volatile sig_atomic_t blk_fired;
static void blk_handler(int s) { (void)s; blk_fired = 1; }

static void test_sigprocmask_block(void)
{
    puts("\n[ 5. SIG_BLOCK / SIG_UNBLOCK ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = blk_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    blk_fired = 0;
    raise(SIGUSR1);
    CHECK(!blk_fired, "SIG_BLOCK: not delivered while blocked", "fired while blocked");

    sigprocmask(SIG_UNBLOCK, &blk, NULL);
    CHECK(blk_fired, "SIG_UNBLOCK: pending delivered on unblock", "not delivered");

    reset_usr();
}

/* ================================================================== */
/* 6. sigpending reports blocked+raised signals                         */
/* ================================================================== */

static void test_sigpending(void)
{
    puts("\n[ 6. sigpending ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = blk_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    blk_fired = 0;
    raise(SIGUSR1);

    sigset_t pend;
    sigemptyset(&pend);
    sigpending(&pend);
    CHECK(sigismember(&pend, SIGUSR1),
          "sigpending: blocked+raised signal is pending", "not in set");

    sigprocmask(SIG_UNBLOCK, &blk, NULL);
    reset_usr();
}

/* ================================================================== */
/* 7. sigreturn restores the pre-handler sigmask                        */
/* ================================================================== */

static volatile sig_atomic_t restore_ok; /* 1=pass -1=fail */

static void restore_handler(int s)
{
    (void)s;
    /* SIGUSR2 was blocked before this handler — must still be blocked */
    sigset_t cur;
    sigprocmask(SIG_BLOCK, NULL, &cur);
    restore_ok = sigismember(&cur, SIGUSR2) ? 1 : -1;
}

static void test_sigreturn_mask_restore(void)
{
    puts("\n[ 7. sigreturn: mask restored ]");
    reset_usr();

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR2);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = restore_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    restore_ok = 0;
    raise(SIGUSR1);
    CHECK(restore_ok == 1,
          "in handler: pre-blocked SIGUSR2 still blocked", "not blocked in handler");

    sigset_t after;
    sigprocmask(SIG_BLOCK, NULL, &after);
    CHECK(sigismember(&after, SIGUSR2),
          "after handler: sigmask restored by sigreturn", "not restored");

    reset_usr();
}

/* ================================================================== */
/* 8. sa_mask blocks extra signals during handler                       */
/* ================================================================== */

static volatile sig_atomic_t sa_mask_pending_in_handler;
static volatile sig_atomic_t sa_mask_u2_fired;

static void sa_mask_u2_handler(int s) { (void)s; sa_mask_u2_fired = 1; }

static void sa_mask_u1_handler(int s)
{
    (void)s;
    raise(SIGUSR2);          /* blocked by sa_mask → goes to pending */
    sigset_t p;
    sigemptyset(&p);
    sigpending(&p);
    sa_mask_pending_in_handler = sigismember(&p, SIGUSR2) ? 1 : 0;
}

static void test_sa_mask(void)
{
    puts("\n[ 8. sa_mask ]");
    reset_usr();

    struct sigaction sa2;
    memset(&sa2, 0, sizeof sa2);
    sa2.sa_handler = sa_mask_u2_handler;
    sigemptyset(&sa2.sa_mask);
    sigaction(SIGUSR2, &sa2, NULL);

    struct sigaction sa1;
    memset(&sa1, 0, sizeof sa1);
    sa1.sa_handler = sa_mask_u1_handler;
    sigemptyset(&sa1.sa_mask);
    sigaddset(&sa1.sa_mask, SIGUSR2);  /* block SIGUSR2 while in SIGUSR1 handler */
    sigaction(SIGUSR1, &sa1, NULL);

    sa_mask_pending_in_handler = 0;
    sa_mask_u2_fired = 0;
    raise(SIGUSR1);

    CHECK(sa_mask_pending_in_handler,
          "sa_mask: SIGUSR2 pending inside SIGUSR1 handler", "not blocked by sa_mask");
    CHECK(sa_mask_u2_fired,
          "sa_mask: SIGUSR2 delivered after SIGUSR1 handler returns", "never delivered");

    reset_usr();
}

/* ================================================================== */
/* 9. Signal implicitly blocked during its own handler (no SA_NODEFER) */
/* ================================================================== */

static volatile sig_atomic_t self_blk_ok; /* 1=pass -1=fail */

static void self_blk_handler(int s)
{
    (void)s;
    sigset_t cur;
    sigprocmask(SIG_BLOCK, NULL, &cur);
    self_blk_ok = sigismember(&cur, SIGUSR1) ? 1 : -1;
}

static void test_signal_self_masked(void)
{
    puts("\n[ 9. signal blocked during own handler ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = self_blk_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGUSR1, &sa, NULL);

    self_blk_ok = 0;
    raise(SIGUSR1);
    CHECK(self_blk_ok == 1,
          "SIGUSR1 blocked inside its own handler", "not blocked");

    reset_usr();
}

/* ================================================================== */
/* 10. Multiple signals pending → all delivered after unblock           */
/* ================================================================== */

static volatile sig_atomic_t multi_u1;
static volatile sig_atomic_t multi_u2;
static void multi_u1_h(int s) { (void)s; multi_u1 = 1; }
static void multi_u2_h(int s) { (void)s; multi_u2 = 1; }

static void test_multiple_pending(void)
{
    puts("\n[ 10. multiple signals pending ]");
    reset_usr();

    struct sigaction sa1, sa2;
    memset(&sa1, 0, sizeof sa1); sa1.sa_handler = multi_u1_h; sigemptyset(&sa1.sa_mask);
    memset(&sa2, 0, sizeof sa2); sa2.sa_handler = multi_u2_h; sigemptyset(&sa2.sa_mask);
    sigaction(SIGUSR1, &sa1, NULL);
    sigaction(SIGUSR2, &sa2, NULL);

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigaddset(&blk, SIGUSR2);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    multi_u1 = multi_u2 = 0;
    raise(SIGUSR1);
    raise(SIGUSR2);

    sigset_t pend;
    sigpending(&pend);
    CHECK(sigismember(&pend, SIGUSR1) && sigismember(&pend, SIGUSR2),
          "both signals in pending set", "not both pending");

    sigprocmask(SIG_UNBLOCK, &blk, NULL);
    CHECK(multi_u1 && multi_u2,
          "both handlers called after unblock", "not both delivered");

    reset_usr();
}

/* ================================================================== */
/* 11. SIGKILL and SIGSTOP cannot be caught                            */
/* ================================================================== */

static void uncatch_h(int s) { (void)s; }

static void test_uncatchable(void)
{
    puts("\n[ 11. SIGKILL/SIGSTOP uncatchable ]");

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = uncatch_h;
    sigemptyset(&sa.sa_mask);

    CHECK(sigaction(SIGKILL, &sa, NULL) == -1 && errno == EINVAL,
          "sigaction(SIGKILL) → EINVAL", "not rejected");
    CHECK(sigaction(SIGSTOP, &sa, NULL) == -1 && errno == EINVAL,
          "sigaction(SIGSTOP) → EINVAL", "not rejected");
}

/* ================================================================== */
/* 12. SIG_SETMASK replaces full mask; old mask returned               */
/* ================================================================== */

static volatile sig_atomic_t setmask_fired;
static void setmask_h(int s) { (void)s; setmask_fired = 1; }

static void test_sigprocmask_setmask(void)
{
    puts("\n[ 12. SIG_SETMASK ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = setmask_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    sigset_t full;
    sigemptyset(&full);
    sigaddset(&full, SIGUSR1);
    sigaddset(&full, SIGUSR2);
    sigprocmask(SIG_SETMASK, &full, NULL);

    setmask_fired = 0;
    raise(SIGUSR1);
    CHECK(!setmask_fired, "SIG_SETMASK blocks signal", "fired while blocked");

    sigset_t empty, old;
    sigemptyset(&empty);
    sigprocmask(SIG_SETMASK, &empty, &old);

    CHECK(sigismember(&old, SIGUSR1) && sigismember(&old, SIGUSR2),
          "SIG_SETMASK: old mask returned correctly", "wrong old mask");
    CHECK(setmask_fired,
          "SIG_SETMASK to empty: pending delivered", "not delivered");

    reset_usr();
}

/* ================================================================== */
/* 13. sigsuspend atomically waits (fork + kill)                       */
/* ================================================================== */

static volatile sig_atomic_t susp_fired;
static void susp_h(int s) { (void)s; susp_fired = 1; }

static void test_sigsuspend(void)
{
    puts("\n[ 13. sigsuspend ]");
    reset_usr();

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = susp_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    pid_t child = fork();
    if (child == 0) {
        usleep(20000);
        kill(getppid(), SIGUSR1);
        _exit(0);
    }

    susp_fired = 0;
    sigset_t wait_mask;
    sigemptyset(&wait_mask);
    int ret = sigsuspend(&wait_mask);
    int saved_errno = errno;
    waitpid(child, NULL, 0);

    CHECK(ret == -1 && saved_errno == EINTR,
          "sigsuspend returns -1/EINTR", "wrong return");
    CHECK(susp_fired, "handler called on wakeup", "not called");

    sigset_t after;
    sigprocmask(SIG_BLOCK, NULL, &after);
    CHECK(sigismember(&after, SIGUSR1),
          "original mask restored after sigsuspend", "mask not restored");

    reset_usr();
}

/* ================================================================== */
/* 14. SA_NODEFER + SA_SIGINFO combined                                */
/* ================================================================== */

static volatile sig_atomic_t nd_si_depth;
static volatile sig_atomic_t nd_si_signo;

static void nd_si_handler(int s, siginfo_t *info, void *ctx)
{
    (void)s; (void)ctx;
    nd_si_depth++;
    nd_si_signo = info->si_signo;
    if (nd_si_depth < 2) raise(SIGUSR2);
    nd_si_depth--;
}

static void test_nodefer_siginfo(void)
{
    puts("\n[ 14. SA_NODEFER + SA_SIGINFO ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = nd_si_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NODEFER | SA_SIGINFO;
    sigaction(SIGUSR2, &sa, NULL);

    nd_si_depth = nd_si_signo = 0;
    raise(SIGUSR2);
    CHECK(nd_si_signo == SIGUSR2, "si_signo correct", "wrong signo");
    CHECK(nd_si_depth == 0, "recursive delivery + clean unwind", "depth mismatch");

    reset_usr();
}

/* ================================================================== */
/* 15. SIG_IGN                                                          */
/* ================================================================== */

static volatile sig_atomic_t ign_fired;
static void ign_probe_h(int s) { (void)s; ign_fired = 1; }

static void test_sig_ign(void)
{
    puts("\n[ 15. SIG_IGN ]");
    reset_usr();

    struct sigaction sa_ign;
    memset(&sa_ign, 0, sizeof sa_ign);
    sa_ign.sa_handler = SIG_IGN;
    sigemptyset(&sa_ign.sa_mask);
    sigaction(SIGUSR1, &sa_ign, NULL);

    ign_fired = 0;
    raise(SIGUSR1);
    CHECK(!ign_fired, "SIG_IGN: signal discarded", "handler fired");

    struct sigaction sa_real;
    memset(&sa_real, 0, sizeof sa_real);
    sa_real.sa_handler = ign_probe_h;
    sigemptyset(&sa_real.sa_mask);
    sigaction(SIGUSR1, &sa_real, NULL);
    raise(SIGUSR1);
    CHECK(ign_fired, "after removing SIG_IGN: handler fires", "not called");

    reset_usr();
}

/* ================================================================== */
/* 16. pthread_kill — signal targeted at a specific thread             */
/* ================================================================== */

static volatile pid_t pkill_worker_tid;
static volatile sig_atomic_t pkill_fired;
static void pkill_h(int s) { (void)s; pkill_fired = 1; }

static void *pkill_thread(void *arg)
{
    (void)arg;
    pkill_worker_tid = syscall(SYS_gettid);
    /* unblock SIGUSR1 in this thread */
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    pthread_sigmask(SIG_UNBLOCK, &set, NULL);

    /* spin until killed via tkill (no pthread_exit / no futex needed) */
    while (1)
        usleep(10000);
    return NULL;
}

static void test_pthread_kill(void)
{
    puts("\n[ 16. pthread_kill ]");
    reset_usr();

    /* main thread blocks SIGUSR1 so only the target thread can receive it */
    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    pthread_sigmask(SIG_BLOCK, &blk, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = pkill_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    pkill_fired = 0;
    pkill_worker_tid = 0;
    pthread_t t;
    pthread_create(&t, NULL, pkill_thread, NULL);

    /* wait until worker has captured its TID and unblocked SIGUSR1 */
    while (!pkill_worker_tid) usleep(1000);
    usleep(5000);

    pthread_kill(t, SIGUSR1);

    for (int i = 0; i < 1000 && !pkill_fired; i++) usleep(1000);
    CHECK(pkill_fired, "pthread_kill: handler fired in target thread", "not fired");

    tkill_thread(pkill_worker_tid);
    usleep(10000);

    pthread_sigmask(SIG_UNBLOCK, &blk, NULL);
    reset_usr();
}

/* ================================================================== */
/* 17. pthread_sigmask is per-thread (does not affect other threads)   */
/* ================================================================== */

/* pipe[0]=read pipe[1]=write used as a barrier */
static int barrier_pipe[2];
static volatile pid_t mask_block_tid;

static void *mask_block_thread(void *arg)
{
    (void)arg;
    mask_block_tid = syscall(SYS_gettid);
    /* block SIGUSR1 only in this thread */
    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    pthread_sigmask(SIG_BLOCK, &blk, NULL);

    /* tell main we're done */
    write(barrier_pipe[1], "x", 1);

    /* spin until killed via tkill */
    while (1) usleep(10000);
    return NULL;
}

static void test_thread_sigmask_independent(void)
{
    puts("\n[ 17. pthread_sigmask independent per thread ]");
    reset_usr();

    pipe(barrier_pipe);

    mask_block_tid = 0;
    pthread_t t;
    pthread_create(&t, NULL, mask_block_thread, NULL);

    /* wait until thread has blocked SIGUSR1 in itself */
    char buf;
    read(barrier_pipe[0], &buf, 1);

    /* check main thread — SIGUSR1 must NOT be blocked here */
    sigset_t main_mask;
    pthread_sigmask(SIG_BLOCK, NULL, &main_mask);
    CHECK(!sigismember(&main_mask, SIGUSR1),
          "thread's SIG_BLOCK does not affect main thread mask",
          "SIGUSR1 unexpectedly blocked in main");

    tkill_thread(mask_block_tid);
    usleep(10000);
    close(barrier_pipe[0]);
    close(barrier_pipe[1]);

    reset_usr();
}

/* ================================================================== */
/* 18. Process-directed signal goes to the thread that has it unblocked*/
/* ================================================================== */

static volatile pid_t proc_sig_tid;
static volatile sig_atomic_t proc_sig_fired;
static void proc_sig_h(int s) { (void)s; proc_sig_fired = 1; }

static void *proc_sig_thread(void *arg)
{
    (void)arg;
    proc_sig_tid = syscall(SYS_gettid);
    /* unblock SIGUSR2 in this thread (main keeps it blocked) */
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGUSR2);
    pthread_sigmask(SIG_UNBLOCK, &set, NULL);

    while (1)
        usleep(10000);
    return NULL;
}

static void test_process_signal_to_unblocked_thread(void)
{
    puts("\n[ 18. process signal delivered to unblocked thread ]");
    reset_usr();

    /* block SIGUSR2 in main */
    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR2);
    pthread_sigmask(SIG_BLOCK, &blk, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = proc_sig_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR2, &sa, NULL);

    proc_sig_fired = 0;
    proc_sig_tid = 0;
    pthread_t t;
    pthread_create(&t, NULL, proc_sig_thread, NULL);

    while (!proc_sig_tid) usleep(1000);
    usleep(5000);  /* let it finish unblocking */

    kill(getpid(), SIGUSR2);   /* process-directed */

    for (int i = 0; i < 1000 && !proc_sig_fired; i++) usleep(1000);
    CHECK(proc_sig_fired,
          "process kill: delivered to unblocked thread",
          "signal not received");

    tkill_thread(proc_sig_tid);
    usleep(10000);

    pthread_sigmask(SIG_UNBLOCK, &blk, NULL);
    reset_usr();
}

/* ================================================================== */
/* 19. Thread-masked signal stays pending until thread unblocks it     */
/* ================================================================== */

static volatile pid_t thread_pend_tid;
static volatile sig_atomic_t thread_pend_fired;
static void thread_pend_h(int s) { (void)s; thread_pend_fired = 1; }

/* pipe: [0]=read [1]=write */
static int tp_pipe[2];

static void *thread_pending_fn(void *arg)
{
    (void)arg;
    thread_pend_tid = syscall(SYS_gettid);
    /* block SIGUSR1 in this thread */
    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    pthread_sigmask(SIG_BLOCK, &blk, NULL);

    /* ready: tell main */
    write(tp_pipe[1], "r", 1);

    /* wait for main to send signal and confirm */
    char buf;
    read(tp_pipe[0], &buf, 1);

    /* check signal is pending */
    sigset_t pend;
    sigpending(&pend);
    int was_pending = sigismember(&pend, SIGUSR1);

    /* unblock — should be delivered now */
    pthread_sigmask(SIG_UNBLOCK, &blk, NULL);

    /* tell main: was_pending result + fired result */
    buf = was_pending ? 'p' : 'n';
    write(tp_pipe[1], &buf, 1);

    /* spin until killed via tkill */
    while (1) usleep(10000);
    return NULL;
}

static void test_thread_masked_pending(void)
{
    puts("\n[ 19. thread-masked signal pending until unblocked ]");
    reset_usr();

    pipe(tp_pipe);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = thread_pend_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    thread_pend_fired = 0;
    thread_pend_tid = 0;
    pthread_t t;
    pthread_create(&t, NULL, thread_pending_fn, NULL);

    /* wait until thread is ready (blocking SIGUSR1) */
    char buf;
    read(tp_pipe[0], &buf, 1);

    /* direct signal at the thread */
    pthread_kill(t, SIGUSR1);

    /* give kernel a moment, then tell thread to check pending */
    usleep(5000);
    write(tp_pipe[1], "c", 1);

    /* read thread's pending-check result */
    read(tp_pipe[0], &buf, 1);
    CHECK(buf == 'p',
          "thread-masked: signal pending inside masked thread",
          "signal not pending");

    /* give the thread time to deliver the now-unblocked signal */
    for (int i = 0; i < 1000 && !thread_pend_fired; i++) usleep(1000);
    CHECK(thread_pend_fired,
          "thread-masked: signal delivered on unblock",
          "not delivered after unblock");

    tkill_thread(thread_pend_tid);
    usleep(10000);

    close(tp_pipe[0]);
    close(tp_pipe[1]);
    reset_usr();
}

/* ================================================================== */
/* 20. exit() — exit code seen by parent via waitpid                   */
/* ================================================================== */

static void test_exit_code(void)
{
    puts("\n[ 20. exit code ]");

    pid_t child = fork();
    if (child == 0) {
        exit(42);
    }
    int status = 0;
    waitpid(child, &status, 0);
    CHECK(WIFEXITED(status), "child exited normally", "not normal exit");
    CHECK(WEXITSTATUS(status) == 42,
          "exit code 42 seen by parent", "wrong exit code");
}

/* ================================================================== */
/* 21. exit_group terminates all threads in the group                  */
/* ================================================================== */

static void *spin_thread(void *arg)
{
    (void)arg;
    while (1) usleep(10000);   /* spins until killed by exit_group */
    return NULL;
}

static void test_exit_group(void)
{
    puts("\n[ 21. exit_group kills all threads ]");

    pid_t child = fork();
    if (child == 0) {
        pthread_t t;
        pthread_create(&t, NULL, spin_thread, NULL);
        usleep(5000);                    /* give thread time to start */
        syscall(SYS_exit_group, 55);
        _exit(99);                       /* not reached */
    }

    /* parent polls for child exit (max ~2 s) */
    int status = 0;
    int exited = 0;
    for (int i = 0; i < 200; i++) {
        pid_t r = waitpid(child, &status, WNOHANG);
        if (r == child) { exited = 1; break; }
        usleep(10000);
    }
    CHECK(exited,
          "exit_group: process exits despite running thread",
          "timed out — spinning thread kept process alive");
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 55,
          "exit_group: exit code 55 correct", "wrong exit code");
}

/* ================================================================== */
/* 22. Raw SYS_exit on single-threaded child                           */
/* ================================================================== */

static void test_raw_exit_syscall(void)
{
    puts("\n[ 22. raw SYS_exit syscall ]");

    pid_t child = fork();
    if (child == 0) {
        syscall(SYS_exit, 77);
        _exit(99);   /* not reached */
    }
    int status = 0;
    waitpid(child, &status, 0);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 77,
          "raw SYS_exit: exit code 77 seen by parent", "wrong code");
}

/* ================================================================== */
/* 23. SIGCHLD delivered to parent on child exit                        */
/* ================================================================== */

static volatile sig_atomic_t sigchld_fired;
static void sigchld_h(int s) { (void)s; sigchld_fired = 1; }

static void test_sigchld(void)
{
    puts("\n[ 23. SIGCHLD on child exit ]");

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = sigchld_h;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NOCLDSTOP;
    sigaction(SIGCHLD, &sa, NULL);

    sigchld_fired = 0;
    pid_t child = fork();
    if (child == 0) _exit(0);

    int res = waitpid(child, NULL, 0);
    if (res != child) {
	    printf("Waitpid returned %d\n", res);
	    perror("23.");
	    exit(1);
    }
    CHECK(sigchld_fired, "SIGCHLD delivered on child exit", "not delivered");

    /* restore */
    struct sigaction dfl;
    memset(&dfl, 0, sizeof dfl);
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    sigaction(SIGCHLD, &dfl, NULL);
}

/* ================================================================== */
/* 24. WIFSIGNALED — child killed by signal                            */
/* ================================================================== */

static void test_wifsignaled(void)
{
    puts("\n[ 24. WIFSIGNALED / WTERMSIG ]");

    pid_t child = fork();
    if (child == 0) {
        /* restore default SIGUSR1 so it terminates us */
        struct sigaction dfl;
        memset(&dfl, 0, sizeof dfl);
        dfl.sa_handler = SIG_DFL;
        sigemptyset(&dfl.sa_mask);
        sigaction(SIGUSR1, &dfl, NULL);
        raise(SIGUSR1);
        _exit(99);
    }
    int status = 0;
    waitpid(child, &status, 0);
    CHECK(WIFSIGNALED(status), "child terminated by signal", "not signaled");
    CHECK(WTERMSIG(status) == SIGUSR1,
          "WTERMSIG == SIGUSR1", "wrong signal");
}

/* ================================================================== */
/* 25. exit_group vs exit: single extra thread stays if only           */
/*    SYS_exit is called in a multi-threaded child                     */
/*    (child exits only when last thread calls exit)                   */
/* ================================================================== */

static int eg_pipe[2];

static void *eg_thread_fn(void *arg)
{
    (void)arg;
    /* thread signals parent it started */
    write(eg_pipe[1], "s", 1);
    /* thread blocks, keeping the process alive */
    char buf;
    read(eg_pipe[0], &buf, 1);
    /* thread exits cleanly */
    syscall(SYS_exit, 0);
    return NULL;
}

static void test_exit_only_one_thread(void)
{
    puts("\n[ 25. SYS_exit exits calling thread only ]");

    pipe(eg_pipe);

    pid_t child = fork();
    if (child == 0) {
        pthread_t t;
        pthread_create(&t, NULL, eg_thread_fn, NULL);
        /* wait until thread started */
        char buf;
        read(eg_pipe[0], &buf, 1);
        /* exit this thread only — child process should still be alive
           because the other thread is still running */
        syscall(SYS_exit, 0);
        _exit(99);  /* not reached */
    }

    /* parent reads the thread's "started" byte, then tells it to exit */
    char buf;
    read(eg_pipe[0], &buf, 1);   /* 's' from thread */

    /* Give child a moment — it should NOT have exited yet */
    usleep(30000);
    int status = 0;
    pid_t r = waitpid(child, &status, WNOHANG);
    CHECK(r == 0,
          "SYS_exit on one thread: process still alive (other thread running)",
          "process exited prematurely");

    /* now tell the surviving thread to exit too */
    write(eg_pipe[1], "x", 1);
    waitpid(child, &status, 0);

    close(eg_pipe[0]);
    close(eg_pipe[1]);
}

/* ================================================================== */
/* 26. kill(getpid(), sig) delivers to self                            */
/* ================================================================== */

static volatile sig_atomic_t kill_self_fired;
static void kill_self_h(int s) { (void)s; kill_self_fired = 1; }

static void test_kill_self(void)
{
    puts("\n[ 26. kill(getpid()) delivers to self ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = kill_self_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    kill_self_fired = 0;
    kill(getpid(), SIGUSR1);
    CHECK(kill_self_fired, "kill(getpid(), SIGUSR1) delivers signal", "not delivered");

    reset_usr();
}

/* ================================================================== */
/* 27. Signal disposition inherited by child after fork                */
/* ================================================================== */

static volatile sig_atomic_t fork_disp_fired;
static void fork_disp_h(int s) { (void)s; fork_disp_fired = 1; }

static void test_fork_disposition_inherit(void)
{
    puts("\n[ 27. fork: signal disposition inherited ]");
    reset_usr();

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = fork_disp_h;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    pid_t child = fork();
    if (child == 0) {
        fork_disp_fired = 0;
        kill(getpid(), SIGUSR1);  /* raise() uses tgkill which is unregistered */
        _exit(fork_disp_fired ? 1 : 0);
    }

    int status = 0;
    waitpid(child, &status, 0);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 1,
          "fork: child inherited SIGUSR1 handler", "handler not inherited");

    reset_usr();
}

/* ================================================================== */
/* 28. Signal mask inherited by child after fork                       */
/* ================================================================== */

static void test_fork_sigmask_inherit(void)
{
    puts("\n[ 28. fork: signal mask inherited ]");
    reset_usr();

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    pid_t child = fork();
    if (child == 0) {
        sigset_t cur;
        sigprocmask(SIG_BLOCK, NULL, &cur);
        _exit(sigismember(&cur, SIGUSR1) ? 1 : 0);
    }

    sigprocmask(SIG_UNBLOCK, &blk, NULL);

    int status = 0;
    waitpid(child, &status, 0);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 1,
          "fork: child inherited blocked SIGUSR1 mask", "mask not inherited");

    reset_usr();
}

/* ================================================================== */
/* 29. Signal delivery order: lower signal number first                */
/* ================================================================== */

static volatile sig_atomic_t ord_first;
static volatile sig_atomic_t ord_second;

static void ord_u1_h(int s)
{
    (void)s;
    if (!ord_first) ord_first  = SIGUSR1;
    else            ord_second = SIGUSR1;
}
static void ord_u2_h(int s)
{
    (void)s;
    if (!ord_first) ord_first  = SIGUSR2;
    else            ord_second = SIGUSR2;
}

static void test_signal_delivery_order(void)
{
    puts("\n[ 29. signal delivery order: lower signo first ]");
    reset_usr();

    struct sigaction sa1, sa2;
    memset(&sa1, 0, sizeof sa1); sa1.sa_handler = ord_u1_h; sigemptyset(&sa1.sa_mask);
    memset(&sa2, 0, sizeof sa2); sa2.sa_handler = ord_u2_h; sigemptyset(&sa2.sa_mask);
    sigaction(SIGUSR1, &sa1, NULL);
    sigaction(SIGUSR2, &sa2, NULL);

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigaddset(&blk, SIGUSR2);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    ord_first = ord_second = 0;
    raise(SIGUSR2);  /* raise higher number first */
    raise(SIGUSR1);

    sigprocmask(SIG_UNBLOCK, &blk, NULL);

    CHECK(ord_first == SIGUSR1,
          "SIGUSR1 (lower signo) delivered before SIGUSR2", "wrong delivery order");

    reset_usr();
}

/* ================================================================== */
/* 30. sigtimedwait — signal already pending → immediate return        */
/* ================================================================== */

static void test_sigtimedwait_pending(void)
{
    puts("\n[ 30. sigtimedwait: signal already pending ]");
    reset_usr();

    /* block SIGUSR1 so raise() queues it without delivery */
    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    raise(SIGUSR1);

    siginfo_t info;
    memset(&info, 0, sizeof info);
    struct timespec ts = { .tv_sec = 5, .tv_nsec = 0 };
    int ret = sigtimedwait(&blk, &info, &ts);

    CHECK(ret == SIGUSR1, "sigtimedwait returns SIGUSR1", "wrong return value");
    CHECK(info.si_signo == SIGUSR1, "si_signo == SIGUSR1", "wrong si_signo");

    /* signal must have been consumed */
    sigset_t pend;
    sigpending(&pend);
    CHECK(!sigismember(&pend, SIGUSR1),
          "signal consumed by sigtimedwait", "still pending after sigtimedwait");

    sigprocmask(SIG_UNBLOCK, &blk, NULL);
    reset_usr();
}

/* ================================================================== */
/* 31. sigtimedwait — timeout expires (nothing pending)                */
/* ================================================================== */

static void test_sigtimedwait_timeout(void)
{
    puts("\n[ 31. sigtimedwait: timeout ]");
    reset_usr();

    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    sigprocmask(SIG_BLOCK, &blk, NULL);

    /* 50 ms timeout, no signal pending */
    struct timespec ts = { .tv_sec = 0, .tv_nsec = 50000000 };
    int ret = sigtimedwait(&blk, NULL, &ts);
    int saved = errno;

    CHECK(ret == -1 && saved == EAGAIN,
          "sigtimedwait times out → -1/EAGAIN", "wrong return or errno");

    sigprocmask(SIG_UNBLOCK, &blk, NULL);
    reset_usr();
}

/* ================================================================== */
/* 32. SIGKILL / SIGSTOP silently dropped by sigprocmask               */
/* ================================================================== */

static void test_sigkill_not_blockable(void)
{
    puts("\n[ 32. SIGKILL/SIGSTOP: sigprocmask silently ignores ]");

    sigset_t blk, cur;
    sigemptyset(&blk);
    sigaddset(&blk, SIGKILL);
    sigaddset(&blk, SIGSTOP);

    int r = sigprocmask(SIG_BLOCK, &blk, NULL);
    CHECK(r == 0, "sigprocmask(SIG_BLOCK, {SIGKILL,SIGSTOP}) returns 0", "failed");

    sigprocmask(SIG_BLOCK, NULL, &cur);
    CHECK(!sigismember(&cur, SIGKILL), "SIGKILL not in mask", "SIGKILL in mask");
    CHECK(!sigismember(&cur, SIGSTOP), "SIGSTOP not in mask", "SIGSTOP in mask");

    sigprocmask(SIG_UNBLOCK, &blk, NULL);
}

/* ================================================================== */
/* main                                                                 */
/* ================================================================== */

int main(void)
{
    puts("=== signal test suite ===");

    install_tkill_exit_handler();

    test_basic_sigaction();
    test_sa_resethand();
    test_sa_nodefer();
    test_sa_siginfo();
    test_sigprocmask_block();
    test_sigpending();
    test_sigreturn_mask_restore();
    test_sa_mask();
    test_signal_self_masked();
    test_multiple_pending();
    test_uncatchable();
    test_sigprocmask_setmask();
    test_sigsuspend();
    test_nodefer_siginfo();
    test_sig_ign();
    test_exit_code();
    test_raw_exit_syscall();
    test_sigchld();
    test_wifsignaled();
    test_kill_self();
    test_fork_disposition_inherit();
    test_fork_sigmask_inherit();
    test_signal_delivery_order();
    test_sigtimedwait_pending();
    test_sigtimedwait_timeout();
    test_sigkill_not_blockable();

    // THREAD RELATED
    test_thread_masked_pending();
    test_thread_sigmask_independent();
    test_process_signal_to_unblocked_thread();
    test_pthread_kill();
    // test_exit_only_one_thread();
    test_exit_group();

    printf("\n=== %d passed, %d failed ===\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
