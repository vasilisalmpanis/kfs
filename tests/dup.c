/*
 * dup, dup2, and descriptor-fcntl conformance tests.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 \
 *     -o test_dup tests/dup.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef F_DUPFD_CLOEXEC
#define F_DUPFD_CLOEXEC 1030
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_TIMEOUT_TICKS 500
#define POST_KILL_TICKS 100

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

static void temp_name(char *buffer, size_t size, const char *tag)
{
    snprintf(buffer, size, "kfs_dup_%ld_%s", (long)getpid(), tag);
}

static int make_file(char *path, size_t size, const char *tag,
                     const char *contents)
{
    int fd;
    size_t length = strlen(contents);

    temp_name(path, size, tag);
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0)
        return -1;
    if (write(fd, contents, length) != (ssize_t)length ||
        lseek(fd, 0, SEEK_SET) != 0) {
        close(fd);
        unlink(path);
        return -1;
    }
    return fd;
}

static int test_dup_lowest(void)
{
    char path[96];
    int source, first, second, replacement, by_fcntl;

    source = make_file(path, sizeof(path), "lowest", "data");
    if (source < 0)
        return failf("file setup: %s", strerror(errno));
    first = dup(source);
    second = dup(source);
    if (first < 0 || second < 0)
        return failf("initial dup: %s", strerror(errno));
    close(first);
    replacement = dup(source);
    if (replacement != first)
        return failf("dup returned %d, lowest free descriptor was %d",
                     replacement, first);
    close(replacement);
    by_fcntl = fcntl(source, F_DUPFD, first);
    if (by_fcntl < 0 && errno == ENOSYS) {
        close(second);
        close(source);
        unlink(path);
        return skipf("F_DUPFD is unsupported");
    }
    if (by_fcntl != first)
        return failf("F_DUPFD returned %d, minimum free descriptor was %d",
                     by_fcntl, first);
    close(by_fcntl);
    close(second);
    close(source);
    unlink(path);
    return TEST_PASS;
}

static int test_dup2_replacement(void)
{
    char source_path[96], target_path[96], buffer[5] = {0};
    int source, target;

    source = make_file(source_path, sizeof(source_path), "source", "AAAA");
    target = make_file(target_path, sizeof(target_path), "target", "BBBB");
    if (source < 0 || target < 0)
        return failf("file setup: %s", strerror(errno));
    if (fcntl(target, F_SETFD, FD_CLOEXEC) < 0)
        return failf("set target CLOEXEC: %s", strerror(errno));
    if (dup2(source, target) != target)
        return failf("dup2 replacement: %s", strerror(errno));
    if (read(target, buffer, 4) != 4 || memcmp(buffer, "AAAA", 4) != 0)
        return failf("replacement descriptor did not refer to source");
    if (fcntl(target, F_GETFD) != 0)
        return failf("dup2 did not clear target FD_CLOEXEC");
    if (read(source, buffer, 1) != 0)
        return failf("dup2 descriptors did not share their offset");
    if (dup2(source, source) != source)
        return failf("dup2(fd, fd) did not return fd unchanged");
    close(target);
    close(source);
    unlink(target_path);
    unlink(source_path);
    return TEST_PASS;
}

static int test_shared_offsets_and_flags(void)
{
    char path[96], buffer[3] = {0};
    int source, copy, flags;

    source = make_file(path, sizeof(path), "shared", "abcdef");
    if (source < 0 || (copy = dup(source)) < 0)
        return failf("setup: %s", strerror(errno));
    if (read(source, buffer, 2) != 2 || memcmp(buffer, "ab", 2) != 0 ||
        read(copy, buffer, 2) != 2 || memcmp(buffer, "cd", 2) != 0)
        return failf("duplicated descriptors did not share offset");

    flags = fcntl(source, F_GETFL);
    if (flags < 0)
        return failf("F_GETFL: %s", strerror(errno));
    if (fcntl(copy, F_SETFL, flags | O_APPEND) != 0 ||
        !(fcntl(source, F_GETFL) & O_APPEND))
        return failf("status flags were not shared after F_SETFL");
    if (fcntl(source, F_SETFL, flags & ~O_APPEND) != 0 ||
        (fcntl(copy, F_GETFL) & O_APPEND))
        return failf("cleared status flag was not shared");
    close(copy);
    close(source);
    unlink(path);
    return TEST_PASS;
}

static int test_close_independence(void)
{
    char path[96], buffer[5] = {0};
    int source, copy;

    source = make_file(path, sizeof(path), "close", "live");
    if (source < 0 || (copy = dup(source)) < 0)
        return failf("setup: %s", strerror(errno));
    close(source);
    if (read(copy, buffer, 4) != 4 || memcmp(buffer, "live", 4) != 0)
        return failf("closing original invalidated duplicate");
    close(copy);
    unlink(path);
    return TEST_PASS;
}

static int test_invalid_descriptors(void)
{
    char path[96];
    int source;

    errno = 0;
    if (dup(-1) != -1 || errno != EBADF)
        return failf("dup(-1) did not return EBADF");
    errno = 0;
    if (dup2(-1, 40) != -1 || errno != EBADF)
        return failf("dup2 with invalid source did not return EBADF");
    errno = 0;
    if (fcntl(-1, F_GETFD) != -1 || errno != EBADF)
        return failf("fcntl on invalid descriptor did not return EBADF");

    source = make_file(path, sizeof(path), "invalid", "x");
    if (source < 0)
        return failf("file setup: %s", strerror(errno));
    close(source);
    errno = 0;
    if (dup(source) != -1 || errno != EBADF)
        return failf("dup of closed descriptor did not return EBADF");
    unlink(path);
    return TEST_PASS;
}

static int test_cloexec_fcntl(void)
{
    char path[96];
    int source, copy, cloexec_copy;
    int initial;

    source = make_file(path, sizeof(path), "cloexec", "x");
    if (source < 0)
        return failf("file setup: %s", strerror(errno));
    errno = 0;
    initial = fcntl(source, F_GETFD);
    if (initial < 0 && errno == ENOSYS) {
        close(source);
        unlink(path);
        return skipf("descriptor flags are unsupported");
    }
    if (initial < 0)
        return failf("F_GETFD: %s", strerror(errno));
    if (fcntl(source, F_SETFD, FD_CLOEXEC) != 0 ||
        fcntl(source, F_GETFD) != FD_CLOEXEC)
        return failf("F_SETFD could not set FD_CLOEXEC");
    if (fcntl(source, F_SETFD, 0) != 0 || fcntl(source, F_GETFD) != 0)
        return failf("F_SETFD could not clear FD_CLOEXEC");

    if (fcntl(source, F_SETFD, FD_CLOEXEC) != 0 ||
        (copy = dup(source)) < 0)
        return failf("dup setup: %s", strerror(errno));
    if (fcntl(copy, F_GETFD) != 0)
        return failf("dup copied FD_CLOEXEC from source");
    cloexec_copy = fcntl(source, F_DUPFD_CLOEXEC, copy + 1);
    if (cloexec_copy < 0 && errno == ENOSYS) {
        close(copy);
        close(source);
        unlink(path);
        return skipf("F_DUPFD_CLOEXEC is unsupported");
    }
    if (cloexec_copy < copy + 1 ||
        fcntl(cloexec_copy, F_GETFD) != FD_CLOEXEC)
        return failf("F_DUPFD_CLOEXEC did not set descriptor flag");
    close(cloexec_copy);
    close(copy);
    close(source);
    unlink(path);
    return TEST_PASS;
}

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "dup lowest-free semantics", test_dup_lowest },
    { "dup2 replacement semantics", test_dup2_replacement },
    { "shared offsets and status flags", test_shared_offsets_and_flags },
    { "close independence", test_close_independence },
    { "invalid descriptors", test_invalid_descriptors },
    { "CLOEXEC descriptor flags", test_cloexec_fcntl },
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
    printf("dup: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed != 0;
}
