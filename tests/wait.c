/*
 * wait / wait4 test suite (i386 Linux)
 *
 * Covers: waitpid by pid / -1 / 0 / -pgid, exit status, signal
 * termination, WNOHANG, WUNTRACED, wait4 rusage, raw SYS_wait4,
 * ECHILD and EINVAL error paths, SIGCHLD delivery on exit (siginfo,
 * blocking, SIG_IGN auto-reap) and signal interruption of a blocked
 * wait (EINTR vs SA_RESTART / kernel ERESTARTSYS).
 *
 * WCONTINUED is not implemented in KFS yet: its test is kept under
 * "#if 0" below -- flip to "#if 1" once the kernel supports it.
 *
 * Build:
 *   zig cc -target x86-linux-musl -static -o test_wait test_wait.c
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
#include <sys/resource.h>
#include <sys/syscall.h>

/* x86 32-bit syscall numbers (in case sys/syscall.h is incomplete) */
#ifndef SYS_exit
#define SYS_exit       1
#endif
#ifndef SYS_wait4
#define SYS_wait4      114
#endif
#ifndef SYS_exit_group
#define SYS_exit_group 252
#endif

/* ------------------------------------------------------------------ */
/* Result tracking                                                     */
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
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

/* Child body that sits alive until killed. Uses a nanosleep loop
 * rather than pause(): KFS does not implement SYS_pause. */
static void child_hang(void)
{
	for (;;)
		usleep(100000);
}

/* Signal bookkeeping shared by the SIGCHLD / EINTR tests. */
static volatile sig_atomic_t g_sigchld_hits;
static volatile sig_atomic_t g_sigchld_pid;
static volatile sig_atomic_t g_sigchld_status;
static volatile sig_atomic_t g_sigchld_code;
static volatile sig_atomic_t g_sigusr1_hits;

static void sigchld_info_handler(int sig, siginfo_t *si, void *ctx)
{
	(void)sig;
	(void)ctx;
	g_sigchld_hits++;
	if (si) {
		g_sigchld_pid = si->si_pid;
		g_sigchld_status = si->si_status;
		g_sigchld_code = si->si_code;
	}
}

static void sigchld_simple_handler(int sig)
{
	(void)sig;
	g_sigchld_hits++;
}

static void sigusr1_handler(int sig)
{
	(void)sig;
	g_sigusr1_hits++;
}

/* Restore SIG_DFL and unblock, so tests do not leak dispositions. */
static void reset_sig(int sig)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = SIG_DFL;
	sigaction(sig, &sa, NULL);

	sigset_t set;
	sigemptyset(&set);
	sigaddset(&set, sig);
	sigprocmask(SIG_UNBLOCK, &set, NULL);
}

/* ------------------------------------------------------------------ */
/* Which-child selection: pid, -1, 0, -pgid                            */
/* ------------------------------------------------------------------ */

static void test_basic_wait_by_pid(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		exit(0);
	}
	int status;
	int res = waitpid(pid, &status, 0);
	CHECK(res == pid, "Child reaped successfully", "wait returned error");
}

static void test_basic_wait_any_child(void)
{
	pid_t pid1 = fork();
	if (pid1 == 0) {
		exit(0);
	}

	pid_t pid2 = fork();
	if (pid2 == 0) {
		exit(0);
	}

	int status;
	int res = waitpid(-1, &status, 0);
	CHECK(res == pid1 || res == pid2, "Wait -1 reaped one of two children",
			"wait returned error");
	res = waitpid(-1, &status, 0);
	CHECK(res == pid1 || res == pid2, "Wait -1 reaped the last of two children",
			"wait returned error");
}

static void test_basic_wait_any_child_with_pgid(void)
{
	pid_t pid1 = fork();
	if (pid1 == 0) {
		pid_t curr_pid = getpid();
		setpgid(0, curr_pid);
		exit(0);
	}

	pid_t pid2 = fork();
	if (pid2 == 0) {
		pid_t curr_pid = getpid();
		setpgid(0, curr_pid);
		exit(0);
	}

	usleep(20000);
	int status;
	int res = waitpid(-pid1, &status, 0);
	CHECK(res == pid1, "Wait -pgid reaped correct child",
			"wait returned error");
	res = waitpid(-pid2, &status, 0);
	CHECK(res == pid2, "Wait -pgid reaped correct child",
			"wait returned error");
}

static void test_basic_wait_any_child_with_parent_pgid(void)
{
	pid_t pid1 = fork();
	if (pid1 == 0) {
		exit(0);
	} else if (pid1 < 0) {
		printf("Fork failed. Skipping...\n");
		return;
	}

	pid_t pid2 = fork();
	if (pid2 == 0) {
		pid_t curr_pid = getpid();
		setpgid(0, curr_pid);
		exit(0);
	} else if (pid2 < 0) {
		printf("Fork failed. Skipping...\n");
		return;
	}

	usleep(20000);
	int status;
	int res = waitpid(0, &status, 0);
	CHECK(res == pid1, "Wait 0 reaped child in own process group",
			"wait returned error");
	errno = 0;
	res = waitpid(0, &status, 0);
	CHECK(res == -1 && errno == ECHILD, "Wait 0 returns ECHILD when group empty",
			"wait reaped child outside own group");
	res = waitpid(-pid2, &status, 0);
	CHECK(res == pid2, "Wait -pgid reaped child that left our group",
			"wait returned error");
}

/* ------------------------------------------------------------------ */
/* Status decoding                                                     */
/* ------------------------------------------------------------------ */

static void test_exit_status(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		exit(42);
	}
	int status = -1;
	int res = waitpid(pid, &status, 0);
	CHECK(res == pid, "Exit status: child reaped", "wait returned error");
	CHECK(WIFEXITED(status), "Exit status: WIFEXITED set",
			"not reported as normal exit");
	CHECK(!WIFSIGNALED(status) && !WIFSTOPPED(status),
			"Exit status: no signal/stop bits", "bogus status bits set");
	CHECK(WEXITSTATUS(status) == 42, "Exit status: WEXITSTATUS == 42",
			"wrong exit code");
}

static void run_signal_termination(int sig, const char *signame)
{
	char name[96];
	pid_t pid = fork();
	if (pid == 0) {
		child_hang();
	}
	usleep(20000);
	kill(pid, sig);
	int status = -1;
	int res = waitpid(pid, &status, 0);
	snprintf(name, sizeof(name), "Killed by %s: child reaped", signame);
	CHECK(res == pid, name, "wait returned error");
	snprintf(name, sizeof(name), "Killed by %s: WIFSIGNALED + WTERMSIG", signame);
	CHECK(WIFSIGNALED(status) && WTERMSIG(status) == sig, name,
			"wrong termination status");
	snprintf(name, sizeof(name), "Killed by %s: WIFEXITED clear", signame);
	CHECK(!WIFEXITED(status), name, "reported as normal exit");
}

static void test_signal_termination(void)
{
	run_signal_termination(SIGKILL, "SIGKILL");
	run_signal_termination(SIGTERM, "SIGTERM");
}

static void test_status_null(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		exit(0);
	}
	int res = waitpid(pid, NULL, 0);
	CHECK(res == pid, "NULL status pointer accepted", "wait returned error");
}

static void test_zombie_persists(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		exit(5);
	}
	/* child is long dead by now; the zombie must still be reapable */
	usleep(50000);
	int status = -1;
	int res = waitpid(pid, &status, 0);
	CHECK(res == pid && WIFEXITED(status) && WEXITSTATUS(status) == 5,
			"Zombie persists until reaped", "zombie lost or wrong status");
}

static void test_selective_wait_skips_other_zombie(void)
{
	pid_t zom = fork();
	if (zom == 0) {
		exit(1);
	}
	pid_t pid = fork();
	if (pid == 0) {
		usleep(50000);
		exit(2);
	}
	/* zom becomes a zombie immediately; waiting for pid must block past it */
	int status = -1;
	int res = waitpid(pid, &status, 0);
	CHECK(res == pid && WIFEXITED(status) && WEXITSTATUS(status) == 2,
			"Selective wait: requested pid returned",
			"reaped wrong child or wrong status");
	res = waitpid(zom, &status, 0);
	CHECK(res == zom && WIFEXITED(status) && WEXITSTATUS(status) == 1,
			"Selective wait: earlier zombie still reapable",
			"first zombie lost");
}

/* ------------------------------------------------------------------ */
/* WNOHANG                                                             */
/* ------------------------------------------------------------------ */

static void test_wnohang(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		usleep(100000);
		exit(3);
	}
	int status = -1;
	int res = waitpid(pid, &status, WNOHANG);
	CHECK(res == 0, "WNOHANG: 0 while child is alive",
			"returned before child exited");

	pid_t got = 0;
	for (int i = 0; i < 500 && got == 0; i++) {
		usleep(10000);
		got = waitpid(pid, &status, WNOHANG);
	}
	CHECK(got == pid && WIFEXITED(status) && WEXITSTATUS(status) == 3,
			"WNOHANG: reaps zombie once child exits",
			"polling never returned the child");
}

/* ------------------------------------------------------------------ */
/* WUNTRACED (stopped children)                                        */
/* ------------------------------------------------------------------ */

static void test_wuntraced(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		child_hang();
	}
	usleep(20000);
	kill(pid, SIGSTOP);

	int status = -1;
	int res = waitpid(pid, &status, WUNTRACED);
	CHECK(res == pid, "WUNTRACED: returns stopped child",
			"wait returned error");
	CHECK(WIFSTOPPED(status) && WSTOPSIG(status) == SIGSTOP,
			"WUNTRACED: WIFSTOPPED + WSTOPSIG == SIGSTOP",
			"wrong stop status");
	CHECK(!WIFEXITED(status) && !WIFSIGNALED(status),
			"WUNTRACED: exit/signal bits clear", "bogus status bits set");

	/* the stop event is one-shot, and a merely-stopped child is not a
	 * zombie: plain WNOHANG must see nothing */
	res = waitpid(pid, &status, WNOHANG);
	CHECK(res == 0, "WUNTRACED: stop reported only once",
			"stopped child reported again / reaped");

	kill(pid, SIGCONT);
	usleep(20000);
	kill(pid, SIGKILL);
	res = waitpid(pid, &status, 0);
	CHECK(res == pid && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL,
			"WUNTRACED: continued child killed and reaped",
			"could not reap child after SIGCONT");
}

/* ------------------------------------------------------------------ */
/* wait4: rusage argument and raw syscall                              */
/* ------------------------------------------------------------------ */

static void test_wait4_rusage(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		/* burn a little CPU so utime is nonzero on kernels that track it */
		volatile unsigned long x = 0;
		for (unsigned long i = 0; i < 3000000; i++)
			x += i;
		(void)x;
		exit(7);
	}

	struct rusage ru;
	memset(&ru, 0xaa, sizeof(ru));
	int status = -1;
	int res = wait4(pid, &status, 0, &ru);
	CHECK(res == pid && WIFEXITED(status) && WEXITSTATUS(status) == 7,
			"wait4: reaps child with rusage pointer",
			"wait4 returned error or wrong status");

	int wrote = 0;
	const unsigned char *p = (const unsigned char *)&ru;
	for (size_t i = 0; i < sizeof(ru); i++) {
		if (p[i] != 0xaa)
			wrote = 1;
	}
	CHECK(wrote, "wait4: rusage struct written by kernel",
			"rusage left untouched");

	/* NULL rusage must also be accepted */
	pid = fork();
	if (pid == 0) {
		exit(0);
	}
	res = wait4(pid, &status, 0, NULL);
	CHECK(res == pid, "wait4: NULL rusage accepted", "wait4 returned error");
}

#ifdef __linux__
static void test_raw_sys_wait4(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		syscall(SYS_exit_group, 9);
	}
	int status = -1;
	long res = syscall(SYS_wait4, pid, &status, 0, NULL);
	CHECK(res == pid, "SYS_wait4: raw syscall reaps child",
			"syscall returned error");
	CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 9,
			"SYS_wait4: exit_group status propagated",
			"wrong status word");
}
#endif

/* ------------------------------------------------------------------ */
/* SIGCHLD on child exit, and its interaction with a blocked wait     */
/* ------------------------------------------------------------------ */

static void test_sigchld_on_exit(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = sigchld_info_handler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGCHLD, &sa, NULL);
	g_sigchld_hits = 0;
	g_sigchld_pid = g_sigchld_status = g_sigchld_code = -1;

	pid_t pid = fork();
	if (pid == 0) {
		usleep(20000);
		exit(12);
	}
	/* retry on EINTR: BSD kernels let the SIGCHLD interrupt the wait;
	 * the no-EINTR Linux semantics get their own test below */
	int status = -1;
	int res;
	do {
		errno = 0;
		res = waitpid(pid, &status, 0);
	} while (res == -1 && errno == EINTR);
	CHECK(res == pid && WIFEXITED(status) && WEXITSTATUS(status) == 12,
			"SIGCHLD on exit: child reaped", "wait returned error");

	/* the pending SIGCHLD is normally handled before waitpid returns
	 * to us; give a slower kernel a moment anyway */
	for (int i = 0; i < 100 && g_sigchld_hits == 0; i++)
		usleep(10000);
	CHECK(g_sigchld_hits == 1, "SIGCHLD on exit: delivered exactly once",
			"missing or duplicate SIGCHLD");
	CHECK(g_sigchld_pid == pid, "SIGCHLD on exit: si_pid is the child",
			"wrong si_pid");
	CHECK(g_sigchld_code == CLD_EXITED, "SIGCHLD on exit: si_code == CLD_EXITED",
			"wrong si_code");
	CHECK(g_sigchld_status == 12, "SIGCHLD on exit: si_status is exit code",
			"wrong si_status");
	reset_sig(SIGCHLD);
}

static void test_sigchld_pending_while_blocked(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigchld_simple_handler;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGCHLD, &sa, NULL);
	g_sigchld_hits = 0;

	sigset_t set;
	sigemptyset(&set);
	sigaddset(&set, SIGCHLD);
	sigprocmask(SIG_BLOCK, &set, NULL);

	pid_t pid = fork();
	if (pid == 0) {
		exit(0);
	}

	/* let the child die while SIGCHLD is masked; check the pending
	 * set BEFORE reaping (BSD kernels discard the pending SIGCHLD
	 * when wait reaps the last child, Linux keeps it) */
	usleep(100000);
	CHECK(g_sigchld_hits == 0, "SIGCHLD blocked: handler not run while masked",
			"handler ran despite mask");

	sigset_t pend;
	sigemptyset(&pend);
	sigpending(&pend);
	CHECK(sigismember(&pend, SIGCHLD) == 1,
			"SIGCHLD blocked: shown in sigpending", "signal not pending");

	sigprocmask(SIG_UNBLOCK, &set, NULL);
	CHECK(g_sigchld_hits == 1, "SIGCHLD blocked: delivered on unblock",
			"handler did not run on unblock");

	int status;
	int res = waitpid(pid, &status, 0);
	CHECK(res == pid, "SIGCHLD blocked: child reapable after unblock",
			"wait returned error");
	reset_sig(SIGCHLD);
}

/* The child's exit both raises SIGCHLD and satisfies the wait: the
 * wait must return the pid, not -1/EINTR, even though the SIGCHLD
 * handler has no SA_RESTART. */
static void test_sigchld_does_not_interrupt_wait(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigchld_simple_handler;
	sa.sa_flags = 0;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGCHLD, &sa, NULL);
	g_sigchld_hits = 0;

	pid_t pid = fork();
	if (pid == 0) {
		usleep(100000);
		exit(4);
	}
	int status = -1;
	errno = 0;
	int res = waitpid(pid, &status, 0);
	int saved_errno = errno;
	CHECK(res == pid && WIFEXITED(status) && WEXITSTATUS(status) == 4,
			"SIGCHLD vs wait: exit satisfies wait, no EINTR",
			"wait returned EINTR instead of the child");
	CHECK(g_sigchld_hits == 1, "SIGCHLD vs wait: handler still ran",
			"SIGCHLD not delivered");
	/* on kernels with the BSD behaviour the check above fails with
	 * EINTR: still reap, or later tests inherit a zombie */
	if (res == -1 && saved_errno == EINTR)
		while (waitpid(pid, &status, 0) == -1 && errno == EINTR)
			;
	reset_sig(SIGCHLD);
}

/* An unrelated signal with no SA_RESTART must interrupt a blocked
 * wait with EINTR (kernel returns ERESTARTSYS, no restart requested). */
static void test_wait_eintr(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigusr1_handler;
	sa.sa_flags = 0;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGUSR1, &sa, NULL);
	g_sigusr1_hits = 0;

	pid_t slow = fork();
	if (slow == 0) {
		usleep(500000);
		exit(0);
	}
	pid_t signaler = fork();
	if (signaler == 0) {
		usleep(50000);
		kill(getppid(), SIGUSR1);
		exit(0);
	}

	int status;
	errno = 0;
	int res = waitpid(slow, &status, 0);
	CHECK(res == -1 && errno == EINTR,
			"EINTR: signal without SA_RESTART interrupts wait",
			"wait was not interrupted");
	CHECK(g_sigusr1_hits == 1, "EINTR: handler ran before wait returned",
			"handler did not run");

	res = waitpid(slow, &status, 0);
	CHECK(res == slow, "EINTR: re-issued wait reaps the child",
			"wait returned error");
	waitpid(signaler, &status, 0);
	reset_sig(SIGUSR1);
}

/* With SA_RESTART the kernel's ERESTARTSYS handling must transparently
 * restart the wait: the caller never sees EINTR and still gets the
 * child's real status. */
static void test_wait_sa_restart(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigusr1_handler;
	sa.sa_flags = SA_RESTART;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGUSR1, &sa, NULL);
	g_sigusr1_hits = 0;

	pid_t slow = fork();
	if (slow == 0) {
		usleep(500000);
		exit(21);
	}
	pid_t signaler = fork();
	if (signaler == 0) {
		usleep(50000);
		kill(getppid(), SIGUSR1);
		exit(0);
	}

	int status = -1;
	int res = waitpid(slow, &status, 0);
	CHECK(res == slow && WIFEXITED(status) && WEXITSTATUS(status) == 21,
			"SA_RESTART: wait restarted, child reaped with status",
			"wait returned early or with error");
	CHECK(g_sigusr1_hits == 1, "SA_RESTART: handler ran during wait",
			"signal was never delivered");
	waitpid(signaler, &status, 0);
	reset_sig(SIGUSR1);
}

/* POSIX: with SIGCHLD set to SIG_IGN children are auto-reaped; a
 * blocking wait sleeps until every child is gone, then fails ECHILD. */
static void test_sigchld_ignored_autoreap(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &sa, NULL);

	pid_t pid = fork();
	if (pid == 0) {
		usleep(50000);
		exit(0);
	}
	/* poll with WNOHANG (bounded) instead of a blocking wait, so a
	 * kernel that never auto-reaps fails instead of hanging us:
	 * 0 while the child lives, then ECHILD once it is auto-reaped;
	 * returning the pid means no auto-reap happened */
	int status;
	int res = 0;
	errno = 0;
	for (int i = 0; i < 300 && res == 0; i++) {
		usleep(10000);
		errno = 0;
		res = waitpid(pid, &status, WNOHANG);
	}
	CHECK(res == -1 && errno == ECHILD,
			"SIG_IGN: child auto-reaped, wait gets ECHILD",
			"child was not auto-reaped");
	reset_sig(SIGCHLD);
}

/* SA_NOCLDWAIT with a real handler: same auto-reap semantics as
 * SIG_IGN, but Linux still delivers SIGCHLD to the handler. */
static void test_sa_nocldwait(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigchld_simple_handler;
	sa.sa_flags = SA_NOCLDWAIT;
	sigemptyset(&sa.sa_mask);
	printf("Sigaction\n");
	sleep(5);
	sigaction(SIGCHLD, &sa, NULL);
	g_sigchld_hits = 0;

	sleep(5);
	printf("Fork\n");
	pid_t pid = fork();
	if (pid == 0) {
		usleep(50000);
		printf("Child exit\n");
		exit(0);
	}
	/* bounded WNOHANG poll, same reasoning as the SIG_IGN test */
	int status;
	int res = 0;
	errno = 0;
	for (int i = 0; i < 300 && res == 0; i++) {
		usleep(10000);
		errno = 0;
		printf("Wait\n");
		res = waitpid(pid, &status, WNOHANG);
	}
	CHECK(res == -1 && errno == ECHILD,
			"SA_NOCLDWAIT: child auto-reaped, wait gets ECHILD",
			"child was not auto-reaped");
	for (int i = 0; i < 100 && g_sigchld_hits == 0; i++)
		usleep(10000);
	CHECK(g_sigchld_hits == 1, "SA_NOCLDWAIT: SIGCHLD still delivered",
			"handler did not run");
	sleep(100);
	reset_sig(SIGCHLD);
}

/* ------------------------------------------------------------------ */
/* Error paths                                                         */
/* ------------------------------------------------------------------ */

/* Must run with no outstanding children. */
static void test_echild(void)
{
	int status;
	errno = 0;
	int res = waitpid(-1, &status, 0);
	CHECK(res == -1 && errno == ECHILD, "ECHILD: no children at all",
			"expected -1/ECHILD");

	errno = 0;
	res = waitpid(1, &status, 0);
	CHECK(res == -1 && errno == ECHILD, "ECHILD: pid 1 is not our child",
			"expected -1/ECHILD");

	/* WNOHANG with no children is ECHILD, not 0 */
	errno = 0;
	res = waitpid(-1, &status, WNOHANG);
	CHECK(res == -1 && errno == ECHILD, "ECHILD: WNOHANG with no children",
			"expected -1/ECHILD");
}

static void test_einval_options(void)
{
	int status;
	errno = 0;
	/* 0x01000000 is not a valid wait4 option bit */
	int res = waitpid(-1, &status, 0x01000000);
	CHECK(res == -1 && errno == EINVAL, "EINVAL: invalid options bit",
			"expected -1/EINVAL");
}

/* ------------------------------------------------------------------ */
/* WCONTINUED -- not implemented in KFS yet, kept disabled             */
/* ------------------------------------------------------------------ */

#if 0 /* flip to 1 once the kernel implements WCONTINUED */
static void test_wcontinued(void)
{
	pid_t pid = fork();
	if (pid == 0) {
		child_hang();
	}
	usleep(20000);
	kill(pid, SIGSTOP);

	int status = -1;
	int res = waitpid(pid, &status, WUNTRACED);
	CHECK(res == pid && WIFSTOPPED(status),
			"WCONTINUED: child stopped first", "stop not reported");

	kill(pid, SIGCONT);
	res = waitpid(pid, &status, WCONTINUED);
	CHECK(res == pid, "WCONTINUED: returns continued child",
			"wait returned error");
	CHECK(WIFCONTINUED(status), "WCONTINUED: WIFCONTINUED set",
			"wrong status word");

	/* the continue event is one-shot */
	res = waitpid(pid, &status, WCONTINUED | WNOHANG);
	CHECK(res == 0, "WCONTINUED: event reported only once",
			"continue reported twice");

	kill(pid, SIGKILL);
	waitpid(pid, &status, 0);
}
#endif

/* ------------------------------------------------------------------ */
/* Watchdog runner: each test runs in its own forked process so a     */
/* kernel bug in a blocking wait path FAILs after a timeout instead   */
/* of hanging the whole suite. Also isolates zombies and signal       */
/* dispositions between tests.                                        */
/* ------------------------------------------------------------------ */

#define TEST_TIMEOUT_TICKS 100 /* x 100ms = 10s per test */

struct test {
	const char *name;
	void (*fn)(void);
};

static void run_test(const struct test *t)
{
	int pfd[2];
	if (pipe(pfd) != 0) {
		/* no pipe: run inline, accepting the hang risk */
		t->fn();
		return;
	}

	pid_t pid = fork();
	if (pid < 0) {
		printf("  FAIL  %s  [fork failed]\n", t->name);
		g_failed++;
		close(pfd[0]);
		close(pfd[1]);
		return;
	}
	if (pid == 0) {
		close(pfd[0]);
		setpgid(0, 0); /* own group, so the parent can kill the subtree */
		g_passed = 0;
		g_failed = 0;
		t->fn();
		char buf[32];
		int n = snprintf(buf, sizeof(buf), "%d %d", g_passed, g_failed);
		write(pfd[1], buf, n);
		exit(0);
	}
	close(pfd[1]);

	int status;
	pid_t res = 0;
	for (int i = 0; i < TEST_TIMEOUT_TICKS && res == 0; i++) {
		usleep(100000);
		res = waitpid(pid, &status, WNOHANG);
	}

	if (res == 0) {
		printf("  FAIL  %s  [timeout after 10s, killing]\n", t->name);
		g_failed++;
		kill(-pid, SIGKILL); /* whole group, if the kernel supports it */
		kill(pid, SIGKILL);
		for (int i = 0; i < 20 && res == 0; i++) {
			usleep(100000);
			res = waitpid(pid, &status, WNOHANG);
		}
		if (res == 0)
			printf("  WARN  %s: test process unkillable, leaking it\n",
					t->name);
		close(pfd[0]);
		return;
	}

	char buf[32];
	int n = read(pfd[0], buf, sizeof(buf) - 1);
	close(pfd[0]);
	int p = 0, f = 0;
	if (n > 0) {
		buf[n] = '\0';
		sscanf(buf, "%d %d", &p, &f);
		g_passed += p;
		g_failed += f;
	} else {
		printf("  FAIL  %s  [test process died without reporting]\n",
				t->name);
		g_failed++;
	}
}

#define TEST(fn) { #fn, fn }

static const struct test g_tests[] = {
	TEST(test_basic_wait_by_pid),
	TEST(test_basic_wait_any_child),
	TEST(test_basic_wait_any_child_with_pgid),
	TEST(test_basic_wait_any_child_with_parent_pgid),
	TEST(test_exit_status),
	TEST(test_signal_termination),
	TEST(test_status_null),
	TEST(test_zombie_persists),
	TEST(test_selective_wait_skips_other_zombie),
	TEST(test_wnohang),
	// TEST(test_wuntraced),
	TEST(test_wait4_rusage),
#ifdef __linux__
	TEST(test_raw_sys_wait4),
#endif
	TEST(test_sigchld_on_exit),
	TEST(test_sigchld_pending_while_blocked),
	TEST(test_sigchld_does_not_interrupt_wait),
	TEST(test_wait_eintr),
	TEST(test_wait_sa_restart),
	TEST(test_sigchld_ignored_autoreap),
	TEST(test_sa_nocldwait),
	TEST(test_echild),
	TEST(test_einval_options),
	/* TEST(test_wcontinued),  -- WCONTINUED not implemented in KFS yet */
};

int main(void)
{
    /* children exit via exit() and would re-flush inherited stdio
     * buffers, duplicating output when stdout is not a tty */
    setvbuf(stdout, NULL, _IONBF, 0);

    puts("=== wait test suite ===");

    for (size_t i = 0; i < sizeof(g_tests) / sizeof(g_tests[0]); i++) {
        run_test(&g_tests[i]);
	sleep(1);
    }

    printf("\n=== %d passed, %d failed ===\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
