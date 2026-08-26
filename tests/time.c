/*
 * Clock, sleep, and interval-timer conformance tests.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_time tests/time.c
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
#include <sys/time.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_TIMEOUT_TICKS 500
#define CHILD_WAIT_TICKS 300
#define POST_KILL_TICKS 100
#define CLOCK_WORKERS 4
#define CLOCK_PHASES 64
#define SLEEP_WORKERS 5
#define I386_SYS_CLOCK_GETRES 266

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

static int valid_timespec(const struct timespec *value)
{
    return value->tv_sec >= 0 && value->tv_nsec >= 0 &&
           value->tv_nsec < 1000000000L;
}

static int64_t timespec_ns(const struct timespec *value)
{
    return (int64_t)value->tv_sec * 1000000000LL + value->tv_nsec;
}

static int64_t elapsed_ns(const struct timespec *start,
                          const struct timespec *end)
{
    return timespec_ns(end) - timespec_ns(start);
}

static void cpu_relax(void)
{
#if defined(__i386__) || defined(__x86_64__)
    __asm__ volatile("pause" ::: "memory");
#else
    atomic_signal_fence(memory_order_seq_cst);
#endif
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

static int test_clock_gettime_basic(void)
{
    struct timespec mono_a, mono_b, realtime;

    if (clock_gettime(CLOCK_MONOTONIC, &mono_a) != 0 ||
        clock_gettime(CLOCK_REALTIME, &realtime) != 0 ||
        clock_gettime(CLOCK_MONOTONIC, &mono_b) != 0)
        return failf("clock_gettime: %s", strerror(errno));
    if (!valid_timespec(&mono_a) || !valid_timespec(&mono_b) ||
        !valid_timespec(&realtime))
        return failf("clock_gettime returned an invalid timespec");
    if (timespec_ns(&mono_b) < timespec_ns(&mono_a))
        return failf("CLOCK_MONOTONIC moved backwards");
    return TEST_PASS;
}

static atomic_uint clock_phase;
static atomic_uint clock_done;
static atomic_uint clock_errors;
static int64_t clock_samples[CLOCK_WORKERS];

struct clock_arg {
    unsigned index;
};

static void *clock_worker(void *opaque)
{
    struct clock_arg *arg = opaque;
    int64_t previous = -1;
    unsigned phase;

    for (phase = 1; phase <= CLOCK_PHASES; phase++) {
        struct timespec now;
        int64_t sample;

        while (atomic_load_explicit(&clock_phase, memory_order_acquire) < phase)
            cpu_relax();
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
            atomic_fetch_add_explicit(&clock_errors, 1, memory_order_relaxed);
            sample = previous;
        } else {
            sample = timespec_ns(&now);
            if (sample < previous)
                atomic_fetch_add_explicit(&clock_errors, 1,
                                          memory_order_relaxed);
        }
        previous = sample;
        clock_samples[arg->index] = sample;
        atomic_fetch_add_explicit(&clock_done, 1, memory_order_release);
        while (atomic_load_explicit(&clock_phase, memory_order_acquire) == phase)
            cpu_relax();
    }
    return NULL;
}

static int test_monotonic_across_threads(void)
{
    pthread_t threads[CLOCK_WORKERS];
    struct clock_arg args[CLOCK_WORKERS];
    int64_t previous_max = -1;
    unsigned created = 0;
    unsigned phase, i;

    atomic_store(&clock_phase, 0);
    atomic_store(&clock_done, 0);
    atomic_store(&clock_errors, 0);
    for (i = 0; i < CLOCK_WORKERS; i++) {
        args[i].index = i;
        if (pthread_create(&threads[i], NULL, clock_worker, &args[i]) != 0)
            break;
        created++;
    }
    if (created != CLOCK_WORKERS)
        return failf("created only %u clock workers", created);

    for (phase = 1; phase <= CLOCK_PHASES; phase++) {
        int64_t phase_min, phase_max;

        atomic_store_explicit(&clock_done, 0, memory_order_relaxed);
        atomic_store_explicit(&clock_phase, phase, memory_order_release);
        while (atomic_load_explicit(&clock_done, memory_order_acquire) !=
               CLOCK_WORKERS)
            cpu_relax();
        phase_min = phase_max = clock_samples[0];
        for (i = 1; i < CLOCK_WORKERS; i++) {
            if (clock_samples[i] < phase_min)
                phase_min = clock_samples[i];
            if (clock_samples[i] > phase_max)
                phase_max = clock_samples[i];
        }
        if (phase_min < previous_max)
            atomic_fetch_add(&clock_errors, 1);
        previous_max = phase_max;
    }
    atomic_store_explicit(&clock_phase, CLOCK_PHASES + 1,
                          memory_order_release);
    for (i = 0; i < CLOCK_WORKERS; i++)
        pthread_join(threads[i], NULL);
    if (atomic_load(&clock_errors) != 0)
        return failf("monotonic samples regressed across synchronized threads");
    return TEST_PASS;
}

struct kernel_timespec32 {
    int32_t tv_sec;
    int32_t tv_nsec;
};

static int test_clock_getres_time32(void)
{
#if defined(__i386__) && defined(__linux__)
    struct kernel_timespec32 resolution = {
        (int32_t)0x81234567u, (int32_t)0x89abcdefu
    };
    long result;

    errno = 0;
    result = syscall(I386_SYS_CLOCK_GETRES, CLOCK_MONOTONIC, &resolution);
    if (result != 0)
        return failf("raw SYS_clock_getres: %s", strerror(errno));
    if (resolution.tv_sec == (int32_t)0x81234567u ||
        resolution.tv_nsec == (int32_t)0x89abcdefu)
        return failf("raw SYS_clock_getres left sentinel fields unchanged");
    if (resolution.tv_sec < 0 || resolution.tv_nsec < 0 ||
        resolution.tv_nsec >= 1000000000 ||
        (resolution.tv_sec == 0 && resolution.tv_nsec == 0))
        return failf("invalid time32 resolution: %d.%09d",
                     resolution.tv_sec, resolution.tv_nsec);
    return TEST_PASS;
#else
    return skipf("raw time32 clock_getres probe is i386-only");
#endif
}

static int test_nanosleep_elapsed(void)
{
    struct timespec request = {0, 50000000L};
    struct timespec start, end;
    int64_t elapsed;

    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0 ||
        nanosleep(&request, NULL) != 0 ||
        clock_gettime(CLOCK_MONOTONIC, &end) != 0)
        return failf("nanosleep: %s", strerror(errno));
    elapsed = elapsed_ns(&start, &end);
    if (elapsed < 40000000LL)
        return failf("50ms nanosleep elapsed in %lldns", (long long)elapsed);
    return TEST_PASS;
}

static volatile sig_atomic_t interrupt_seen;

static void interrupt_handler(int signo)
{
    (void)signo;
    interrupt_seen++;
}

static int test_nanosleep_eintr_remainder(void)
{
    struct sigaction action;
    struct timespec request = {0, 500000000L};
    struct timespec remainder = {-1, -1};
    int command[2], ready[2];
    pid_t signaler;
    char byte;
    int result, saved_errno;

    memset(&action, 0, sizeof(action));
    action.sa_handler = interrupt_handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, NULL) != 0 || pipe(command) != 0 ||
        pipe(ready) != 0)
        return failf("signal setup: %s", strerror(errno));
    signaler = fork();
    if (signaler < 0)
        return failf("fork: %s", strerror(errno));
    if (signaler == 0) {
        unsigned attempt;

        close(command[1]);
        close(ready[0]);
        if (write(ready[1], "R", 1) != 1)
            _exit(2);
        if (read(command[0], &byte, 1) != 1)
            _exit(3);
        for (attempt = 0; attempt < 20; attempt++) {
            struct timespec delay = {0, 10000000L};
            struct timespec rem;

            while (nanosleep(&delay, &rem) != 0 && errno == EINTR)
                delay = rem;
            if (kill(getppid(), SIGUSR1) != 0)
                _exit(4);
        }
        _exit(0);
    }
    close(command[0]);
    close(ready[1]);
    interrupt_seen = 0;
    if (read(ready[0], &byte, 1) != 1 || write(command[1], "S", 1) != 1)
        return failf("signaler handshake failed");
    errno = 0;
    result = nanosleep(&request, &remainder);
    saved_errno = errno;
    if (!wait_ok(signaler))
        return failf("signaler failed");
    close(command[1]);
    close(ready[0]);
    if (result != -1 || saved_errno != EINTR || !interrupt_seen)
        return failf("nanosleep was not interrupted by handled signal");
    if (!valid_timespec(&remainder) || timespec_ns(&remainder) <= 0 ||
        timespec_ns(&remainder) >= timespec_ns(&request))
        return failf("invalid EINTR remainder %ld.%09ld",
                     (long)remainder.tv_sec, remainder.tv_nsec);
    return TEST_PASS;
}

struct sleeper_arg {
    long milliseconds;
    int64_t elapsed;
    int error;
};

static atomic_int sleepers_start;

static void *sleeper_worker(void *opaque)
{
    struct sleeper_arg *arg = opaque;
    struct timespec request = {
        arg->milliseconds / 1000,
        (arg->milliseconds % 1000) * 1000000L
    };
    struct timespec start, end;

    while (!atomic_load_explicit(&sleepers_start, memory_order_acquire))
        cpu_relax();
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0 ||
        nanosleep(&request, NULL) != 0 ||
        clock_gettime(CLOCK_MONOTONIC, &end) != 0) {
        arg->error = 1;
        return NULL;
    }
    arg->elapsed = elapsed_ns(&start, &end);
    return NULL;
}

static int test_concurrent_sleepers(void)
{
    static const long delays[SLEEP_WORKERS] = {20, 35, 50, 65, 80};
    struct sleeper_arg args[SLEEP_WORKERS];
    pthread_t threads[SLEEP_WORKERS];
    unsigned created = 0;
    unsigned i;

    atomic_store(&sleepers_start, 0);
    memset(args, 0, sizeof(args));
    for (i = 0; i < SLEEP_WORKERS; i++) {
        args[i].milliseconds = delays[i];
        if (pthread_create(&threads[i], NULL, sleeper_worker, &args[i]) != 0)
            break;
        created++;
    }
    if (created != SLEEP_WORKERS)
        return failf("created only %u sleeper workers", created);
    atomic_store_explicit(&sleepers_start, 1, memory_order_release);
    for (i = 0; i < SLEEP_WORKERS; i++)
        pthread_join(threads[i], NULL);
    for (i = 0; i < SLEEP_WORKERS; i++) {
        int64_t requested = delays[i] * 1000000LL;
        if (args[i].error || args[i].elapsed + 2000000LL < requested)
            return failf("%ldms concurrent deadline elapsed in %lldns",
                         delays[i], (long long)args[i].elapsed);
    }
    return TEST_PASS;
}

static volatile sig_atomic_t alarm_seen;

static void alarm_handler(int signo)
{
    (void)signo;
    alarm_seen = 1;
}

static int test_setitimer_sigalrm(void)
{
    struct sigaction action;
    struct itimerval timer;
    struct timespec pause = {0, 10000000L};
    unsigned attempt;

    memset(&action, 0, sizeof(action));
    action.sa_handler = alarm_handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL) != 0)
        return failf("sigaction(SIGALRM): %s", strerror(errno));
    memset(&timer, 0, sizeof(timer));
    timer.it_value.tv_usec = 50000;
    alarm_seen = 0;
    errno = 0;
    if (setitimer(ITIMER_REAL, &timer, NULL) != 0) {
        if (errno == ENOSYS || errno == EOPNOTSUPP)
            return skipf("setitimer is unsupported");
        return failf("setitimer: %s", strerror(errno));
    }
    for (attempt = 0; attempt < 100 && !alarm_seen; attempt++) {
        struct timespec rem;
        if (nanosleep(&pause, &rem) != 0 && errno != EINTR)
            return failf("wait for SIGALRM: %s", strerror(errno));
    }
    memset(&timer, 0, sizeof(timer));
    (void)setitimer(ITIMER_REAL, &timer, NULL);
    if (!alarm_seen)
        return failf("successful setitimer did not deliver SIGALRM");
    return TEST_PASS;
}

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "CLOCK_MONOTONIC and CLOCK_REALTIME", test_clock_gettime_basic },
    { "monotonic across concurrent threads", test_monotonic_across_threads },

    // TODO: implement getres
    // { "raw i386 clock_getres time32", test_clock_getres_time32 },
    { "nanosleep elapsed time", test_nanosleep_elapsed },
    { "nanosleep EINTR remainder", test_nanosleep_eintr_remainder },
    { "concurrent sleeper deadlines", test_concurrent_sleepers },

    // TODO: implement timers
    // { "setitimer SIGALRM", test_setitimer_sigalrm },
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
    printf("time: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed != 0;
}
