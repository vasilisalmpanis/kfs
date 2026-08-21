/*
 * KFS resource-limit test suite.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -o test_limits tests/limits.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define CHILD_SKIP 77

enum result { TEST_PASS, TEST_FAIL, TEST_SKIP };

static int passed;
static int failed;
static int skipped;

struct resource_entry {
    int resource;
    const char *name;
};

static const struct resource_entry resources[] = {
    { RLIMIT_CPU, "CPU" },
    { RLIMIT_FSIZE, "FSIZE" },
    { RLIMIT_DATA, "DATA" },
    { RLIMIT_STACK, "STACK" },
    { RLIMIT_CORE, "CORE" },
    { RLIMIT_RSS, "RSS" },
    { RLIMIT_NPROC, "NPROC" },
    { RLIMIT_NOFILE, "NOFILE" },
    { RLIMIT_MEMLOCK, "MEMLOCK" },
    { RLIMIT_AS, "AS" },
#ifdef RLIMIT_LOCKS
    { RLIMIT_LOCKS, "LOCKS" },
#endif
#ifdef RLIMIT_SIGPENDING
    { RLIMIT_SIGPENDING, "SIGPENDING" },
#endif
#ifdef RLIMIT_MSGQUEUE
    { RLIMIT_MSGQUEUE, "MSGQUEUE" },
#endif
#ifdef RLIMIT_NICE
    { RLIMIT_NICE, "NICE" },
#endif
#ifdef RLIMIT_RTPRIO
    { RLIMIT_RTPRIO, "RTPRIO" },
#endif
#ifdef RLIMIT_RTTIME
    { RLIMIT_RTTIME, "RTTIME" },
#endif
};

static enum result test_getrlimit_resources(void)
{
    size_t i;

    for (i = 0; i < ARRAY_SIZE(resources); i++) {
        struct rlimit limit;

        if (getrlimit(resources[i].resource, &limit) != 0) {
            printf("  resource %s failed: %s\n",
                   resources[i].name, strerror(errno));
            return TEST_FAIL;
        }
        if (limit.rlim_cur > limit.rlim_max)
            return TEST_FAIL;
    }
    return TEST_PASS;
}

static const int adjustable_resources[] = {
    RLIMIT_CORE, RLIMIT_NOFILE, RLIMIT_STACK
};

static int make_change(int resource, struct rlimit *original,
                       rlim_t *replacement)
{
    if (getrlimit(resource, original) != 0)
        return -2;
    if (original->rlim_max == 0)
        return -1;
    if (original->rlim_cur == RLIM_INFINITY)
        *replacement = 0;
    else if (original->rlim_cur == 0)
        *replacement = 1;
    else
        *replacement = original->rlim_cur - 1;
    return *replacement <= original->rlim_max &&
           *replacement != original->rlim_cur ? 0 : -1;
}

static int setrlimit_round_trip_one(int resource)
{
    struct rlimit original;
    struct rlimit changed;
    struct rlimit observed;
    rlim_t replacement;
    int valid;
    int result = 0;

    valid = make_change(resource, &original, &replacement);
    if (valid != 0)
        return valid;
    changed = original;
    changed.rlim_cur = replacement;
    if (setrlimit(resource, &changed) != 0)
        return 1;
    if (getrlimit(resource, &observed) != 0 ||
        observed.rlim_cur != changed.rlim_cur ||
        observed.rlim_max != changed.rlim_max)
        result = 1;
    if (setrlimit(resource, &original) != 0)
        result = 1;
    return result;
}

static enum result test_setrlimit_round_trip(void)
{
    unsigned exercised = 0;
    size_t i;

    for (i = 0; i < ARRAY_SIZE(adjustable_resources); i++) {
        int result = setrlimit_round_trip_one(adjustable_resources[i]);

        if (result == -1)
            continue;
        if (result != 0)
            return TEST_FAIL;
        exercised++;
    }
    return exercised == 0 ? TEST_SKIP : TEST_PASS;
}

static enum result test_prlimit_query(void)
{
    struct rlimit direct;
    struct rlimit through_prlimit;

    if (getrlimit(RLIMIT_NOFILE, &direct) != 0)
        return TEST_FAIL;
    if (prlimit(0, RLIMIT_NOFILE, NULL, &through_prlimit) != 0)
        return errno == ENOSYS ? TEST_SKIP : TEST_FAIL;
    if (direct.rlim_cur != through_prlimit.rlim_cur ||
        direct.rlim_max != through_prlimit.rlim_max)
        return TEST_FAIL;
    return TEST_PASS;
}

static int prlimit_round_trip_one(int resource)
{
    struct rlimit original;
    struct rlimit changed;
    struct rlimit observed;
    rlim_t replacement;
    int valid;
    int result = 0;

    valid = make_change(resource, &original, &replacement);
    if (valid != 0)
        return valid;
    changed = original;
    changed.rlim_cur = replacement;
    if (prlimit(0, resource, &changed, &observed) != 0)
        return errno == ENOSYS ? -3 : 1;
    if (observed.rlim_cur != original.rlim_cur ||
        observed.rlim_max != original.rlim_max)
        result = 1;
    if (prlimit(0, resource, NULL, &observed) != 0 ||
        observed.rlim_cur != replacement ||
        observed.rlim_max != original.rlim_max)
        result = 1;
    if (prlimit(0, resource, &original, NULL) != 0)
        result = 1;
    return result;
}

static enum result test_prlimit_round_trip(void)
{
    unsigned exercised = 0;
    size_t i;

    for (i = 0; i < ARRAY_SIZE(adjustable_resources); i++) {
        int result = prlimit_round_trip_one(adjustable_resources[i]);

        if (result == -1)
            continue;
        if (result == -3)
            return TEST_SKIP;
        if (result != 0)
            return TEST_FAIL;
        exercised++;
    }
    return exercised == 0 ? TEST_SKIP : TEST_PASS;
}

static enum result test_invalid_resource(void)
{
    struct rlimit limit;
    int result;
    int saved;

    errno = 0;
    if (getrlimit(-1, &limit) != -1 || errno != EINVAL)
        return TEST_FAIL;
    errno = 0;
    result = prlimit(0, -1, NULL, &limit);
    saved = errno;
    if (result == -1 && saved == ENOSYS)
        return TEST_SKIP;
    return result == -1 && saved == EINVAL ? TEST_PASS : TEST_FAIL;
}

static enum result test_invalid_pid(void)
{
    struct rlimit limit;
    int result;
    int saved;

    errno = 0;
    result = prlimit(-1, RLIMIT_CORE, NULL, &limit);
    saved = errno;
    if (result == -1 && saved == ENOSYS)
        return TEST_SKIP;
    return result == -1 && saved == ESRCH ? TEST_PASS : TEST_FAIL;
}

static int child_soft_exceeds_hard(void)
{
    struct rlimit invalid = { 1, 0 };
    struct rlimit before;
    struct rlimit after;
    int result;
    int saved;

    if (getrlimit(RLIMIT_CORE, &before) != 0)
        return 2;
    errno = 0;
    result = setrlimit(RLIMIT_CORE, &invalid);
    saved = errno;
    if (getrlimit(RLIMIT_CORE, &after) != 0)
        return 3;
    return result == -1 && saved == EINVAL &&
           before.rlim_cur == after.rlim_cur &&
           before.rlim_max == after.rlim_max ? 0 : 1;
}

static int child_hard_lowering(void)
{
    struct rlimit zero = { 0, 0 };
    struct rlimit observed;

    if (setrlimit(RLIMIT_CORE, &zero) != 0)
        return 1;
    if (getrlimit(RLIMIT_CORE, &observed) != 0)
        return 2;
    return observed.rlim_cur == 0 && observed.rlim_max == 0 ? 0 : 3;
}

static int child_inheritance(void)
{
    struct rlimit original;
    struct rlimit changed;
    struct rlimit observed;
    rlim_t replacement;
    int resource = -1;
    int status = 0;
    int child_result = CHILD_SKIP;
    pid_t pid;
    unsigned tick;
    size_t i;

    for (i = 0; i < ARRAY_SIZE(adjustable_resources); i++) {
        if (make_change(adjustable_resources[i], &original, &replacement) == 0) {
            resource = adjustable_resources[i];
            break;
        }
    }
    if (resource < 0)
        return CHILD_SKIP;
    changed = original;
    changed.rlim_cur = replacement;
    if (setrlimit(resource, &changed) != 0)
        return 1;
    pid = fork();
    if (pid < 0) {
        child_result = CHILD_SKIP;
        goto restore;
    }
    if (pid == 0) {
        if (getrlimit(resource, &observed) != 0)
            _exit(2);
        _exit(observed.rlim_cur == changed.rlim_cur &&
              observed.rlim_max == changed.rlim_max ? 0 : 3);
    }
    for (tick = 0; tick < 100; tick++) {
        pid_t result = waitpid(pid, &status, WNOHANG);

        if (result == pid)
            break;
        if (result < 0 && errno != EINTR) {
            child_result = 4;
            goto kill_child;
        }
        usleep(10000);
    }
    if (tick == 100) {
kill_child:
        kill(pid, SIGKILL);
        for (tick = 0; tick < 50; tick++) {
            pid_t result = waitpid(pid, &status, WNOHANG);

            if (result == pid)
                break;
            if (result < 0 && errno != EINTR)
                break;
            usleep(10000);
        }
        if (child_result == CHILD_SKIP)
            child_result = 5;
        goto restore;
    }
    child_result = WIFEXITED(status) ? WEXITSTATUS(status) : 4;

restore:
    if (setrlimit(resource, &original) != 0)
        return 6;
    return child_result;
}

static enum result run_child(int (*child)(void))
{
    pid_t pid = fork();
    int status = 0;
    unsigned tick;

    if (pid < 0)
        return TEST_SKIP;
    if (pid == 0) {
        (void)setpgid(0, 0);
        _exit(child());
    }
    for (tick = 0; tick < 50; tick++) {
        pid_t result = waitpid(pid, &status, WNOHANG);

        if (result == pid)
            break;
        if (result < 0 && errno != EINTR) {
            tick = 50;
            break;
        }
        usleep(100000);
    }
    if (tick == 50) {
        kill(-pid, SIGKILL);
        kill(pid, SIGKILL);
        for (tick = 0; tick < 20; tick++) {
            pid_t result = waitpid(pid, &status, WNOHANG);

            if (result == pid)
                break;
            if (result < 0 && errno != EINTR)
                break;
            usleep(100000);
        }
        return TEST_FAIL;
    }
    if (!WIFEXITED(status))
        return TEST_FAIL;
    if (WEXITSTATUS(status) == CHILD_SKIP)
        return TEST_SKIP;
    return WEXITSTATUS(status) == 0 ? TEST_PASS : TEST_FAIL;
}

static enum result isolated_soft_hard_validation(void)
{
    return run_child(child_soft_exceeds_hard);
}

static enum result isolated_hard_lowering(void)
{
    return run_child(child_hard_lowering);
}

static enum result isolated_inheritance(void)
{
    return run_child(child_inheritance);
}

struct test_case {
    const char *name;
    enum result (*run)(void);
};

static const struct test_case tests[] = {
    { "getrlimit resources and soft<=hard", test_getrlimit_resources },
    { "setrlimit soft-limit round trip", test_setrlimit_round_trip },
    { "prlimit query agrees with getrlimit", test_prlimit_query },
    { "prlimit soft-limit round trip", test_prlimit_round_trip },
    { "invalid resource returns EINVAL", test_invalid_resource },
    { "invalid prlimit pid", test_invalid_pid },
    { "soft limit above hard is rejected", isolated_soft_hard_validation },
    { "isolated hard-limit lowering", isolated_hard_lowering },
    { "limits are inherited across fork", isolated_inheritance },
};

int main(void)
{
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    puts("resource limits suite");
    for (i = 0; i < ARRAY_SIZE(tests); i++) {
        enum result result;
        int saved_errno;

        errno = 0;
        result = tests[i].run();
        saved_errno = errno;

        if (result == TEST_PASS) {
            printf("PASS %s\n", tests[i].name);
            passed++;
        } else if (result == TEST_SKIP) {
            printf("SKIP %s [resource or syscall unavailable]\n", tests[i].name);
            skipped++;
        } else {
            if (saved_errno != 0)
                printf("FAIL %s [errno=%d: %s]\n",
                       tests[i].name, saved_errno, strerror(saved_errno));
            else
                printf("FAIL %s [limit value mismatch]\n", tests[i].name);
            failed++;
        }
    }
    printf("SUMMARY pass=%d fail=%d skip=%d\n", passed, failed, skipped);
    return failed != 0;
}
