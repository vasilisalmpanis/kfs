/*
 * poll, select, and pselect conformance tests.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 \
 *     -o test_poll tests/poll.c
 *
 * Every pipe readiness case runs in a watchdog-isolated subprocess because
 * KFS pipe polling is intentionally exercised even when it is incomplete.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_TIMEOUT_TICKS 500
#define CHILD_WAIT_TICKS 300
#define POST_KILL_TICKS 100
#define BLOCK_CONFIRM_TICKS 10
#define MAX_PIPE_CAPACITY (1024u * 1024u)

enum { TEST_PASS = 0, TEST_FAIL = 1, TEST_SKIP = 77 };

static int passed;
static int failed;
static int skipped;

static int failf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stdout);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    return TEST_FAIL;
}

static int skipf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stdout);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    return TEST_SKIP;
}

static long elapsed_ms(const struct timespec *start, const struct timespec *end)
{
    return (long)(end->tv_sec - start->tv_sec) * 1000L +
           (end->tv_nsec - start->tv_nsec) / 1000000L;
}

static int write_exact(int fd, const void *buffer, size_t size)
{
    const unsigned char *p = buffer;

    while (size != 0) {
        ssize_t n = write(fd, p, size);

        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        p += n;
        size -= (size_t)n;
    }
    return 0;
}

static int read_exact(int fd, void *buffer, size_t size)
{
    unsigned char *p = buffer;

    while (size != 0) {
        ssize_t n = read(fd, p, size);

        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        p += n;
        size -= (size_t)n;
    }
    return 0;
}

static pid_t waitpid_bounded(pid_t pid, int *status, unsigned ticks)
{
    unsigned tick;

    for (tick = 0; tick < ticks; tick++) {
        pid_t result = waitpid(pid, status, WNOHANG);

        if (result == pid || (result < 0 && errno != EINTR))
            return result;
        usleep(10000);
    }
    return 0;
}

static int wait_ok(pid_t pid)
{
    int status = 0;
    pid_t result = waitpid_bounded(pid, &status, CHILD_WAIT_TICKS);

    if (result == 0) {
        kill(pid, SIGKILL);
        (void)waitpid_bounded(pid, &status, POST_KILL_TICKS);
        return 0;
    }
    return result == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int make_regular_file(char *path, size_t size)
{
    int fd;

    snprintf(path, size, "kfs_poll_%ld", (long)getpid());
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd >= 0 && write(fd, "x", 1) != 1) {
        close(fd);
        unlink(path);
        return -1;
    }
    return fd;
}

static ssize_t fill_pipe(int fd)
{
    unsigned char data[256];
    size_t total = 0;
    int flags = fcntl(fd, F_GETFL);

    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0)
        return -1;
    memset(data, 0x71, sizeof(data));
    while (total < MAX_PIPE_CAPACITY) {
        ssize_t n = write(fd, data, sizeof(data));

        if (n > 0) {
            total += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return (ssize_t)total;
        return -1;
    }
    errno = EOVERFLOW;
    return -1;
}

static int test_timeout_without_fds(void)
{
    struct timespec start, end;
    int result;

    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0)
        return failf("clock_gettime: %s", strerror(errno));
    result = poll(NULL, 0, 60);
    if (clock_gettime(CLOCK_MONOTONIC, &end) != 0)
        return failf("clock_gettime after poll: %s", strerror(errno));
    if (result != 0)
        return failf("poll(NULL, 0) returned %d", result);
    if (elapsed_ms(&start, &end) < 40)
        return failf("60ms timeout elapsed in %ldms", elapsed_ms(&start, &end));
    if (poll(NULL, 0, 0) != 0)
        return failf("zero timeout with no fds was not immediate success");
    return TEST_PASS;
}

static int test_regular_file_readiness(void)
{
    char path[96];
    struct pollfd pfd;
    int fd = make_regular_file(path, sizeof(path));
    int result;

    if (fd < 0)
        return failf("regular file setup: %s", strerror(errno));
    pfd.fd = fd;
    pfd.events = POLLIN | POLLOUT;
    pfd.revents = 0;
    result = poll(&pfd, 1, 0);
    close(fd);
    unlink(path);
    if (result != 1 || (pfd.revents & (POLLIN | POLLOUT)) !=
                           (POLLIN | POLLOUT))
        return failf("regular file poll returned %d, revents=%#x",
                     result, pfd.revents);
    return TEST_PASS;
}

static int test_empty_pipe_not_readable(void)
{
    int p[2];
    struct pollfd pfd;
    int result;

    if (pipe(p) != 0)
        return failf("pipe: %s", strerror(errno));
    pfd.fd = p[0];
    pfd.events = POLLIN;
    pfd.revents = 0;
    result = poll(&pfd, 1, 0);
    close(p[0]);
    close(p[1]);
    if (result != 0 || pfd.revents != 0)
        return failf("empty pipe incorrectly ready: result=%d revents=%#x",
                     result, pfd.revents);
    return TEST_PASS;
}

static int test_pipe_data_readable(void)
{
    int p[2];
    struct pollfd pfd;
    int result;

    if (pipe(p) != 0 || write_exact(p[1], "D", 1) != 0)
        return failf("pipe setup: %s", strerror(errno));
    pfd.fd = p[0];
    pfd.events = POLLIN;
    pfd.revents = 0;
    result = poll(&pfd, 1, 0);
    close(p[0]);
    close(p[1]);
    if (result != 1 || !(pfd.revents & POLLIN))
        return failf("pipe with data not readable: result=%d revents=%#x",
                     result, pfd.revents);
    return TEST_PASS;
}

static int test_pipe_hangup(void)
{
    int p[2];
    struct pollfd pfd;
    int result;

    if (pipe(p) != 0)
        return failf("pipe: %s", strerror(errno));
    close(p[1]);
    pfd.fd = p[0];
    pfd.events = POLLIN;
    pfd.revents = 0;
    result = poll(&pfd, 1, 0);
    close(p[0]);
    if (result != 1 || !(pfd.revents & POLLHUP))
        return failf("writer close lacked POLLHUP: result=%d revents=%#x",
                     result, pfd.revents);
    return TEST_PASS;
}

static int test_full_pipe_not_writable(void)
{
    int p[2];
    struct pollfd pfd;
    ssize_t capacity;
    int result;

    if (pipe(p) != 0)
        return failf("pipe: %s", strerror(errno));
    capacity = fill_pipe(p[1]);
    if (capacity <= 0)
        return failf("capacity discovery: %s", strerror(errno));
    pfd.fd = p[1];
    pfd.events = POLLOUT;
    pfd.revents = 0;
    result = poll(&pfd, 1, 0);
    close(p[0]);
    close(p[1]);
    if (result != 0 || pfd.revents != 0)
        return failf("full pipe incorrectly writable: result=%d revents=%#x",
                     result, pfd.revents);
    return TEST_PASS;
}

struct poll_result {
    int result;
    short revents;
};

static int test_blocking_pipe_poll_wake(void)
{
    int data[2], report[2];
    pid_t child;
    char ready;
    struct poll_result observed;
    int report_flags;
    unsigned tick;

    if (pipe(data) != 0 || pipe(report) != 0)
        return failf("pipe setup: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        struct pollfd pfd;
        struct poll_result value;

        close(data[1]);
        close(report[0]);
        if (write_exact(report[1], "R", 1) != 0)
            _exit(2);
        pfd.fd = data[0];
        pfd.events = POLLIN;
        pfd.revents = 0;
        value.result = poll(&pfd, 1, 1000);
        value.revents = pfd.revents;
        if (write_exact(report[1], &value, sizeof(value)) != 0)
            _exit(3);
        _exit(0);
    }
    close(data[0]);
    close(report[1]);
    if (read_exact(report[0], &ready, 1) != 0)
        return failf("poller readiness handshake failed");

    /*
     * The ready byte is sent immediately before poll(). Kernel wait-state
     * introspection is unavailable, so the window below proves only that no
     * result was produced while the pipe stayed empty. Checking the report
     * channel before writing makes an erroneous immediate readiness result a
     * deterministic failure rather than a race with the wake write.
     */
    report_flags = fcntl(report[0], F_GETFL);
    if (report_flags < 0 ||
        fcntl(report[0], F_SETFL, report_flags | O_NONBLOCK) != 0)
        return failf("set report channel nonblocking: %s", strerror(errno));
    for (tick = 0; tick < BLOCK_CONFIRM_TICKS; tick++) {
        pid_t state;
        ssize_t n;

        usleep(10000);
        errno = 0;
        n = read(report[0], &observed, sizeof(observed));
        if (n == (ssize_t)sizeof(observed)) {
            (void)wait_ok(child);
            return failf("poll completed before data was written");
        }
        if (n >= 0 || (errno != EAGAIN && errno != EWOULDBLOCK &&
                       errno != EINTR))
            return failf("unexpected early poll report result");
        state = waitpid(child, NULL, WNOHANG);
        if (state == child)
            return failf("poller exited before data was written");
        if (state < 0 && errno != EINTR)
            return failf("poller wait check: %s", strerror(errno));
    }
    if (fcntl(report[0], F_SETFL, report_flags) != 0)
        return failf("restore report channel flags: %s", strerror(errno));
    if (write_exact(data[1], "W", 1) != 0 ||
        read_exact(report[0], &observed, sizeof(observed)) != 0)
        return failf("poll wake coordination failed");
    close(data[1]);
    close(report[0]);
    if (!wait_ok(child))
        return failf("poller process failed");
    if (observed.result != 1 || !(observed.revents & POLLIN))
        return failf("blocking poll returned %d, revents=%#x",
                     observed.result, observed.revents);
    return TEST_PASS;
}

static int test_select_regular_file(void)
{
    char path[96];
    int fd = make_regular_file(path, sizeof(path));
    fd_set reads, writes;
    struct timeval timeout = {0, 0};
    int result;

    if (fd < 0)
        return failf("regular file setup: %s", strerror(errno));
    FD_ZERO(&reads);
    FD_ZERO(&writes);
    FD_SET(fd, &reads);
    FD_SET(fd, &writes);
    result = select(fd + 1, &reads, &writes, NULL, &timeout);
    close(fd);
    unlink(path);
    if (result < 0 && (errno == ENOSYS || errno == EINVAL))
        return skipf("select is unsupported");
    if (result != 2 || !FD_ISSET(fd, &reads) || !FD_ISSET(fd, &writes))
        return failf("select returned %d for regular file", result);
    return TEST_PASS;
}

static int test_pselect_regular_file(void)
{
    char path[96];
    int fd = make_regular_file(path, sizeof(path));
    fd_set reads;
    struct timespec timeout = {0, 0};
    int result;

    if (fd < 0)
        return failf("regular file setup: %s", strerror(errno));
    FD_ZERO(&reads);
    FD_SET(fd, &reads);
    result = pselect(fd + 1, &reads, NULL, NULL, &timeout, NULL);
    close(fd);
    unlink(path);
    if (result < 0 && (errno == ENOSYS || errno == EINVAL))
        return skipf("pselect is unsupported");
    if (result != 1 || !FD_ISSET(fd, &reads))
        return failf("pselect returned %d for regular file", result);
    return TEST_PASS;
}

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "timeout with no descriptors", test_timeout_without_fds },
    { "regular file readiness", test_regular_file_readiness },
    { "empty pipe is not readable", test_empty_pipe_not_readable },
    { "pipe data readiness", test_pipe_data_readable },
    { "pipe hangup readiness", test_pipe_hangup },
    { "full pipe is not writable", test_full_pipe_not_writable },
    { "pipe poll waits for data", test_blocking_pipe_poll_wake },
    { "select regular file", test_select_regular_file },
    { "pselect regular file", test_pselect_regular_file },
};

static void run_isolated(const struct test_case *test)
{
    pid_t child;
    pid_t result = 0;
    int status = 0;
    int code;
    unsigned tick;

    child = fork();
    if (child < 0) {
        printf("FAIL %s (fork: %s)\n", test->name, strerror(errno));
        failed++;
        return;
    }
    if (child == 0) {
        (void)setpgid(0, 0);
        _exit(test->run());
    }
    (void)setpgid(child, child);
    for (tick = 0; tick < TEST_TIMEOUT_TICKS && result == 0; tick++) {
        result = waitpid(child, &status, WNOHANG);
        if (result < 0 && errno == EINTR)
            result = 0;
        if (result == 0)
            usleep(10000);
    }
    if (result == 0) {
        pid_t reaped;

        kill(-child, SIGKILL);
        kill(child, SIGKILL);
        reaped = waitpid_bounded(child, &status, POST_KILL_TICKS);
        printf("FAIL %s (timeout%s)\n", test->name,
               reaped == child ? "" : "; child not reaped");
        failed++;
        return;
    }
    if (result != child) {
        printf("FAIL %s (waitpid: %s)\n", test->name, strerror(errno));
        failed++;
        return;
    }
    code = WIFEXITED(status) ? WEXITSTATUS(status) : TEST_FAIL;
    if (code == TEST_PASS) {
        printf("PASS %s\n", test->name);
        passed++;
    } else if (code == TEST_SKIP) {
        printf("SKIP %s\n", test->name);
        skipped++;
    } else {
        printf("FAIL %s (%s)\n", test->name,
               WIFSIGNALED(status) ? "signal" : "test error");
        failed++;
    }
}

int main(void)
{
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_isolated(&tests[i]);
    printf("poll: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed != 0;
}
