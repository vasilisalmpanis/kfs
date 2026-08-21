/*
 * process identity/group/credential test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_process tests/process.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SYS_gettid
#define SYS_gettid 224
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static int failf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stderr);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    return 1;
}

static pid_t wait_bounded(pid_t pid, int *status, unsigned ticks)
{
    unsigned tick;

    for (tick = 0; tick < ticks; tick++) {
        pid_t got = waitpid(pid, status, WNOHANG);

        if (got < 0 && errno == EINTR)
            continue;
        if (got != 0)
            return got;
        usleep(10000);
    }
    return 0;
}

static void terminate_child(pid_t pid)
{
    int status;
    pid_t got = waitpid(pid, &status, WNOHANG);

    if (got == pid || (got < 0 && errno == ECHILD))
        return;
    (void)kill(pid, SIGKILL);
    (void)wait_bounded(pid, &status, 100);
}

static int wait_status(pid_t pid, int expected)
{
    int status;
    pid_t got = wait_bounded(pid, &status, 200);

    if (got != pid) {
        if (got == 0 || errno != ECHILD)
            terminate_child(pid);
        return 0;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == expected;
}

static int read_byte_bounded(int fd, char *byte)
{
    int flags = fcntl(fd, F_GETFL);
    unsigned tick;

    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0)
        return -1;
    for (tick = 0; tick < 100; tick++) {
        ssize_t count = read(fd, byte, 1);

        if (count == 1)
            return 0;
        if (count == 0)
            return -1;
        if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
            return -1;
        usleep(10000);
    }
    return -1;
}

static int test_basic_ids(void)
{
    pid_t pid = getpid();
    pid_t ppid = getppid();
    pid_t tid = (pid_t)syscall(SYS_gettid);

    if (pid <= 0 || ppid <= 0 || tid <= 0)
        return failf("getpid/getppid/gettid returned a nonpositive ID");
    if (tid != pid)
        return failf("single-threaded main TID %ld != PID %ld",
                     (long)tid, (long)pid);
    if (ppid == pid)
        return failf("process reported itself as its parent");
    return 0;
}

static int test_fork_parent_relation(void)
{
    int report[2];
    pid_t parent = getpid();
    pid_t child;
    pid_t observed = -1;

    if (pipe(report) != 0)
        return failf("pipe failed: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork failed: %s", strerror(errno));
    if (child == 0) {
        pid_t ppid = getppid();

        close(report[0]);
        if (write(report[1], &ppid, sizeof(ppid)) != (ssize_t)sizeof(ppid))
            _exit(2);
        _exit(0);
    }
    close(report[1]);
    if (read(report[0], &observed, sizeof(observed)) !=
        (ssize_t)sizeof(observed)) {
        terminate_child(child);
        return failf("could not read child's parent ID");
    }
    close(report[0]);
    if (!wait_status(child, 0) || observed != parent)
        return failf("fork child reported wrong parent");
    return 0;
}

static int test_process_group_basics(void)
{
    pid_t pid = getpid();

    if (setpgid(0, 0) != 0)
        return failf("setpgid self failed: %s", strerror(errno));
    if (getpgrp() != pid || getpgid(0) != pid || getpgid(pid) != pid)
        return failf("process group getters disagreed");

    errno = 0;
    if (getpgid(-1) != -1 || (errno != EINVAL && errno != ESRCH))
        return failf("getpgid(-1) returned unexpected result/errno");
    errno = 0;
    if (setpgid(0, -1) != -1 || errno != EINVAL)
        return failf("setpgid with negative pgid did not return EINVAL");
    return 0;
}

static int test_session_basics(void)
{
    pid_t child = fork();

    if (child < 0)
        return failf("fork failed: %s", strerror(errno));
    if (child == 0) {
        pid_t sid = setsid();

        if (sid != getpid())
            _exit(2);
        if (getsid(0) != sid || getpgrp() != sid || getpgid(0) != sid)
            _exit(3);
        errno = 0;
        if (setsid() != -1 || errno != EPERM)
            _exit(4);
        _exit(0);
    }
    if (!wait_status(child, 0))
        return failf("setsid/getsid semantics failed");
    errno = 0;
    if (getsid(-1) != -1 || (errno != EINVAL && errno != ESRCH))
        return failf("getsid(-1) returned unexpected result/errno");
    return 0;
}

static volatile sig_atomic_t group_signal_seen;

static void group_signal_handler(int sig)
{
    (void)sig;
    group_signal_seen = 1;
}

static void group_child(int ready_fd, pid_t group, int leader)
{
    struct sigaction action;
    char ready = 'R';
    unsigned tick;

    memset(&action, 0, sizeof(action));
    action.sa_handler = group_signal_handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, NULL) != 0)
        _exit(2);
    if (setpgid(0, leader ? 0 : group) != 0)
        _exit(3);
    group_signal_seen = 0;
    if (write(ready_fd, &ready, 1) != 1)
        _exit(4);
    for (tick = 0; tick < 200 && !group_signal_seen; tick++)
        usleep(10000);
    _exit(group_signal_seen ? 0 : 5);
}

static int test_process_group_signal(void)
{
    int leader_ready[2];
    int member_ready[2];
    pid_t leader = -1;
    pid_t member = -1;
    int leader_live = 0;
    int member_live = 0;
    int status;
    pid_t got;
    char byte;

    if (pipe(leader_ready) != 0 || pipe(member_ready) != 0)
        return failf("pipe failed: %s", strerror(errno));
    leader = fork();
    if (leader < 0)
        return failf("leader fork failed: %s", strerror(errno));
    if (leader == 0) {
        close(leader_ready[0]);
        close(member_ready[0]);
        close(member_ready[1]);
        group_child(leader_ready[1], 0, 1);
    }
    leader_live = 1;
    close(leader_ready[1]);
    if (read_byte_bounded(leader_ready[0], &byte) != 0 || byte != 'R') {
        (void)kill(-leader, SIGKILL);
        terminate_child(leader);
        return failf("group leader did not become ready");
    }

    member = fork();
    if (member < 0) {
        int saved_errno = errno;

        (void)kill(-leader, SIGKILL);
        terminate_child(leader);
        return failf("member fork failed: %s", strerror(saved_errno));
    }
    if (member == 0) {
        close(leader_ready[0]);
        close(member_ready[0]);
        group_child(member_ready[1], leader, 0);
    }
    member_live = 1;
    close(member_ready[1]);
    if (setpgid(member, leader) != 0) {
        int saved_errno = errno;

        (void)kill(-leader, SIGKILL);
        terminate_child(leader);
        terminate_child(member);
        return failf("could not join child to process group: %s",
                     strerror(saved_errno));
    }
    if (read_byte_bounded(member_ready[0], &byte) != 0 || byte != 'R') {
        (void)kill(-leader, SIGKILL);
        terminate_child(leader);
        terminate_child(member);
        return failf("process-group member did not become ready");
    }
    close(leader_ready[0]);
    close(member_ready[0]);
    if (kill(-leader, SIGUSR1) != 0) {
        int saved_errno = errno;

        (void)kill(-leader, SIGKILL);
        terminate_child(leader);
        terminate_child(member);
        return failf("process-group kill failed: %s", strerror(saved_errno));
    }

    got = wait_bounded(leader, &status, 250);
    if (got == leader)
        leader_live = 0;
    if (got != leader || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (leader_live)
            terminate_child(leader);
        if (member_live)
            terminate_child(member);
        return failf("process-group leader had wrong status");
    }
    got = wait_bounded(member, &status, 250);
    if (got == member)
        member_live = 0;
    if (got != member || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (member_live)
            terminate_child(member);
        return failf("signal did not reach every process-group member");
    }
    return 0;
}

static int test_credential_getters(void)
{
    uid_t uid = getuid();
    gid_t gid = getgid();

    if (geteuid() != uid || getegid() != gid)
        return failf("real/effective credential getters disagreed");
    if (setuid(uid) != 0 || setgid(gid) != 0)
        return failf("setting current credentials was rejected");
    if (getuid() != uid || geteuid() != uid ||
        getgid() != gid || getegid() != gid)
        return failf("no-op credential setters changed credentials");
    return 0;
}

static int test_credential_setters_and_errors(void)
{
    uid_t uid = geteuid();
    uid_t other = uid == 123 ? 124 : 123;

    if (uid == 0) {
        if (setgid(123) != 0 || setuid(123) != 0)
            return failf("privileged credential drop failed: %s",
                         strerror(errno));
        if (getuid() != 123 || geteuid() != 123 ||
            getgid() != 123 || getegid() != 123)
            return failf("credential drop was not visible to getters");
        other = 124;
    }

    errno = 0;
    if (setuid(other) != -1 || errno != EPERM)
        return failf("unprivileged setuid did not return EPERM");
    errno = 0;
    if (setgroups(0, NULL) != -1 || errno != EPERM)
        return failf("unprivileged setgroups did not return EPERM");
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "getpid/getppid/gettid", test_basic_ids },
    { "fork parent relationship", test_fork_parent_relation },
    { "process group basics and errors", test_process_group_basics },
    { "session creation and errors", test_session_basics },
    { "isolated process-group signaling", test_process_group_signal },
    { "credential getters/no-op setters", test_credential_getters },
    { "isolated credential drop/errors", test_credential_setters_and_errors },
};

static void run_test(const struct test_case *test, int *passed, int *failed)
{
    pid_t pid = fork();
    pid_t got = 0;
    int status = 0;
    unsigned tick;

    if (pid == 0) {
        (void)setpgid(0, 0);
        _exit(test->fn());
    }
    if (pid < 0) {
        printf("FAIL  %s [fork: %s]\n", test->name, strerror(errno));
        (*failed)++;
        return;
    }
    /* Internal escaped-descendant cleanup is bounded below this 10s limit. */
    for (tick = 0; tick < 1000 && got == 0; tick++) {
        usleep(10000);
        got = waitpid(pid, &status, WNOHANG);
        if (got < 0 && errno == EINTR)
            got = 0;
    }
    if (got == 0) {
        (void)kill(-pid, SIGKILL);
        terminate_child(pid);
        printf("FAIL  %s [timeout]\n", test->name);
        (*failed)++;
    } else if (got == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        printf("PASS  %s\n", test->name);
        (*passed)++;
    } else if (got == pid && WIFSIGNALED(status)) {
        (void)kill(-pid, SIGKILL);
        printf("FAIL  %s [signal %d]\n", test->name, WTERMSIG(status));
        (*failed)++;
    } else {
        if (got == pid)
            (void)kill(-pid, SIGKILL);
        else if (errno != ECHILD) {
            (void)kill(-pid, SIGKILL);
            terminate_child(pid);
        }
        printf("FAIL  %s [status %d]\n", test->name,
               WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        (*failed)++;
    }
}

int main(void)
{
    int passed = 0;
    int failed = 0;
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_test(&tests[i], &passed, &failed);
    printf("SUMMARY process: %d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
