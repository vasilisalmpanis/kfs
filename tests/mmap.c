/*
 * mmap/munmap test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_mmap tests/mmap.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MAP_SHARED_VALIDATE
#define MAP_SHARED_VALIDATE 0x03
#endif

#define PAGE_SIZE 4096u
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_SKIP 77

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

static int wait_ok(pid_t pid, int expected)
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

static int test_anonymous_memory(void)
{
    unsigned char *a;
    unsigned char *b;
    size_t i;

    a = mmap(NULL, 2 * PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    b = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (a == MAP_FAILED || b == MAP_FAILED)
        return failf("anonymous mmap failed: %s", strerror(errno));
    if (a == b)
        return failf("separate mappings returned the same address");
    for (i = 0; i < 2 * PAGE_SIZE; i++) {
        if (a[i] != 0)
            return failf("anonymous byte %zu was not zero", i);
        a[i] = (unsigned char)(i * 37u + 11u);
    }
    for (i = 0; i < 2 * PAGE_SIZE; i++) {
        if (a[i] != (unsigned char)(i * 37u + 11u))
            return failf("read/write mismatch at byte %zu", i);
    }
    b[0] = 0xa5;
    if (a[0] == b[0])
        return failf("separate mappings aliased unexpectedly");
    if (munmap(a, 2 * PAGE_SIZE) != 0 || munmap(b, PAGE_SIZE) != 0)
        return failf("munmap failed: %s", strerror(errno));
    return 0;
}

static int test_unmap_and_hint(void)
{
    unsigned char *old;
    unsigned char *fresh;

    old = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (old == MAP_FAILED)
        return failf("initial mmap failed: %s", strerror(errno));
    old[0] = 0x5a;
    if (munmap(old, PAGE_SIZE) != 0)
        return failf("munmap failed: %s", strerror(errno));

    /* A non-MAP_FIXED address is only a hint; either address is valid. */
    fresh = mmap(old, PAGE_SIZE, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (fresh == MAP_FAILED)
        return failf("hinted remap failed: %s", strerror(errno));
    if (fresh[0] != 0)
        return failf("remapped page was not freshly zeroed");
    fresh[0] = 0xc3;
    if (fresh[0] != 0xc3 || munmap(fresh, PAGE_SIZE) != 0)
        return failf("hinted mapping was not writable/unmappable");
    return 0;
}

static int test_invalid_arguments(void)
{
    void *p;

    errno = 0;
    p = mmap(NULL, 0, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p != MAP_FAILED) {
        (void)munmap(p, 0);
        return failf("zero-length mmap succeeded");
    }
    if (errno != EINVAL)
        return failf("zero-length mmap errno %d, expected EINVAL", errno);

    errno = 0;
    p = mmap(NULL, PAGE_SIZE, PROT_READ, MAP_PRIVATE, 123456, 0);
    if (p != MAP_FAILED || errno != EBADF) {
        if (p != MAP_FAILED)
            (void)munmap(p, PAGE_SIZE);
        return failf("invalid fd did not return EBADF");
    }

    errno = 0;
    p = mmap(NULL, PAGE_SIZE, PROT_READ,
             MAP_SHARED_VALIDATE | MAP_ANONYMOUS | 0x80000000u, -1, 0);
    if (p != MAP_FAILED) {
        (void)munmap(p, PAGE_SIZE);
        return failf("unsupported mmap flag succeeded");
    }
    if (errno != EINVAL && errno != EOPNOTSUPP && errno != ENOTSUP)
        return failf("unsupported flag returned unexpected errno %d", errno);

    p = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return failf("setup mmap failed: %s", strerror(errno));
    errno = 0;
    if (munmap((char *)p + 1, PAGE_SIZE) != -1 || errno != EINVAL)
        return failf("unaligned munmap did not return EINVAL");
    if (munmap(p, PAGE_SIZE) != 0)
        return failf("cleanup munmap failed");
    return 0;
}

static int test_map_fixed(void)
{
    uint32_t *p;
    uint32_t *q;

    p = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return failf("setup mmap failed: %s", strerror(errno));
    p[0] = 0x11223344u;
    q = mmap(p, PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (q == MAP_FAILED)
        return failf("MAP_FIXED failed: %s", strerror(errno));
    if (q != p)
        return failf("MAP_FIXED returned the wrong address");
    if (q[0] != 0)
        return failf("MAP_FIXED replacement retained old contents");
    q[0] = 0xaabbccddu;
    if (q[0] != 0xaabbccddu || munmap(q, PAGE_SIZE) != 0)
        return failf("MAP_FIXED replacement was unusable");
    return 0;
}

static int test_fork_private(void)
{
    volatile uint32_t *p;
    pid_t pid;

    p = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return failf("private mmap failed: %s", strerror(errno));
    p[0] = 0x12345678u;
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        if (p[0] != 0x12345678u)
            _exit(2);
        p[0] = 0x87654321u;
        _exit(p[0] == 0x87654321u ? 0 : 3);
    }
    if (!wait_ok(pid, 0))
        return failf("child could not use its private mapping");
    if (p[0] != 0x12345678u)
        return failf("child write changed parent's private mapping");
    if (munmap((void *)p, PAGE_SIZE) != 0)
        return failf("private mapping cleanup failed");
    return 0;
}

static int test_fork_shared(void)
{
    volatile uint32_t *p;
    pid_t pid;

    errno = 0;
    p = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        if (errno == EINVAL || errno == ENOSYS || errno == EOPNOTSUPP ||
            errno == ENOTSUP)
            return TEST_SKIP;
        return failf("shared anonymous mmap failed: %s", strerror(errno));
    }
    p[0] = 1;
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        p[0] = 0xfeedbeefu;
        _exit(0);
    }
    if (!wait_ok(pid, 0))
        return failf("shared-mapping child failed");
    if (p[0] != 0xfeedbeefu)
        return failf("MAP_SHARED update was not visible after fork");
    if (munmap((void *)p, PAGE_SIZE) != 0)
        return failf("shared mapping cleanup failed");
    return 0;
}

#define MMAP_THREADS 4
#define MMAP_ROUNDS 100
static _Atomic unsigned stress_errors;

static void *stress_worker(void *opaque)
{
    uintptr_t id = (uintptr_t)opaque;
    unsigned round;

    for (round = 0; round < MMAP_ROUNDS; round++) {
        uint32_t *p = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
                           MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        uint32_t value = (uint32_t)((id + 1) << 24) ^ round;

        if (p == MAP_FAILED) {
            atomic_fetch_add(&stress_errors, 1);
            continue;
        }
        p[0] = value;
        p[PAGE_SIZE / sizeof(*p) - 1] = ~value;
        if (p[0] != value || p[PAGE_SIZE / sizeof(*p) - 1] != ~value)
            atomic_fetch_add(&stress_errors, 1);
        if (munmap(p, PAGE_SIZE) != 0)
            atomic_fetch_add(&stress_errors, 1);
    }
    return NULL;
}

static int test_concurrent_stress(void)
{
    pthread_t threads[MMAP_THREADS];
    unsigned created = 0;
    unsigned i;

    atomic_store(&stress_errors, 0);
    for (i = 0; i < MMAP_THREADS; i++) {
        int rc = pthread_create(&threads[i], NULL, stress_worker,
                                (void *)(uintptr_t)i);
        if (rc != 0) {
            unsigned j;

            for (j = 0; j < created; j++)
                (void)pthread_join(threads[j], NULL);
            return failf("pthread_create %u failed: %s", i, strerror(rc));
        }
        created++;
    }
    for (i = 0; i < MMAP_THREADS; i++) {
        int rc = pthread_join(threads[i], NULL);
        if (rc != 0)
            return failf("pthread_join %u failed: %s", i, strerror(rc));
    }
    if (atomic_load(&stress_errors) != 0)
        return failf("mmap stress observed %u errors",
                     atomic_load(&stress_errors));
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "anonymous zero-fill/read-write/separation", test_anonymous_memory },
    { "munmap and non-fixed remap hint", test_unmap_and_hint },
    { "invalid length/flags/fd/alignment", test_invalid_arguments },
    { "MAP_FIXED replacement", test_map_fixed },
    { "fork MAP_PRIVATE isolation", test_fork_private },
    { "fork MAP_SHARED visibility", test_fork_shared },
    { "concurrent pthread mmap/munmap", test_concurrent_stress },
};

static void run_test(const struct test_case *test, int *passed, int *failed,
                     int *skipped)
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
    for (tick = 0; tick < 500 && got == 0; tick++) {
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
    } else if (got != pid) {
        int saved_errno = errno;

        (void)kill(-pid, SIGKILL);
        if (saved_errno != ECHILD)
            terminate_child(pid);
        printf("FAIL  %s [waitpid: %s]\n", test->name,
               strerror(saved_errno));
        (*failed)++;
    } else if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        printf("PASS  %s\n", test->name);
        (*passed)++;
    } else if (WIFEXITED(status) && WEXITSTATUS(status) == TEST_SKIP) {
        printf("SKIP  %s [unsupported]\n", test->name);
        (*skipped)++;
    } else if (WIFSIGNALED(status)) {
        (void)kill(-pid, SIGKILL);
        printf("FAIL  %s [signal %d]\n", test->name, WTERMSIG(status));
        (*failed)++;
    } else {
        (void)kill(-pid, SIGKILL);
        printf("FAIL  %s [status %d]\n", test->name,
               WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        (*failed)++;
    }
}

int main(void)
{
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_test(&tests[i], &passed, &failed, &skipped);
    printf("SUMMARY mmap: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed ? 1 : 0;
}
