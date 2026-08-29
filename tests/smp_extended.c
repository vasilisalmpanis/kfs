/*
 * Extended SMP userspace tests (i386 Linux ABI).
 *
 * Cross-CPU assertions are skipped when only one APIC ID is observed.
 * Every test is isolated in a process group and has a 20-second watchdog.
 *
 * Build:
 *   zig cc -target x86-linux-musl -static -O2 -pthread -o smp_extended tests/smp_extended.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SYS_futex
#define SYS_futex 240
#endif
#ifndef SYS_nanosleep
#define SYS_nanosleep 162
#endif
#ifndef SYS_gettid
#define SYS_gettid 224
#endif
#ifndef SYS_exit_group
#define SYS_exit_group 252
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define CPU_MASK_WORDS 8

enum test_result {
    TEST_OK = 0,
    TEST_FAILED = 1,
    TEST_NEEDS_SMP = 2,
    TEST_SKIP = 3,
};

static int g_passed;
static int g_failed;
static int g_skipped;

_Static_assert(ATOMIC_INT_LOCK_FREE == 2,
               "signal-handler bookkeeping requires lock-free atomic int");

static void cpu_relax(void)
{
#if defined(__i386__) || defined(__x86_64__)
    __asm__ volatile("pause" ::: "memory");
#endif
}

static unsigned current_apic_id(void)
{
#if defined(__i386__) || defined(__x86_64__)
    unsigned eax = 1;
    unsigned ebx;
    unsigned ecx = 0;
    unsigned edx;

    __asm__ volatile("cpuid"
                     : "+a"(eax), "=b"(ebx), "+c"(ecx), "=d"(edx)
                     :
                     : "memory");
    return ebx >> 24;
#else
    return 0;
#endif
}

static pid_t raw_gettid(void)
{
#if defined(__i386__)
    long result;

    __asm__ volatile("int $0x80"
                     : "=a"(result)
                     : "0"((long)SYS_gettid)
                     : "memory", "cc");
    return (pid_t)result;
#else
    return (pid_t)syscall(SYS_gettid);
#endif
}

static _Noreturn void raw_exit_group(int status)
{
#if defined(__i386__)
    long result;

    __asm__ volatile("int $0x80"
                     : "=a"(result)
                     : "0"((long)SYS_exit_group), "b"((long)status)
                     : "memory", "cc");
    (void)result;
#else
    (void)syscall(SYS_exit_group, status);
#endif
    _exit(124);
}

static int failf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stdout);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    return TEST_FAILED;
}

static int full_read(int fd, void *buffer, size_t size)
{
    unsigned char *p = buffer;
    size_t done = 0;

    while (done < size) {
        ssize_t result = read(fd, p + done, size - done);

        if (result > 0) {
            done += (size_t)result;
            continue;
        }
        if (result < 0 && errno == EINTR)
            continue;
        return -1;
    }
    return 0;
}

static int full_write(int fd, const void *buffer, size_t size)
{
    const unsigned char *p = buffer;
    size_t done = 0;

    while (done < size) {
        ssize_t result = write(fd, p + done, size - done);

        if (result > 0) {
            done += (size_t)result;
            continue;
        }
        if (result < 0 && errno == EINTR)
            continue;
        return -1;
    }
    return 0;
}

static int write_once(int fd, const void *buffer, size_t size)
{
    ssize_t result;

    do {
        result = write(fd, buffer, size);
    } while (result < 0 && errno == EINTR);
    return result == (ssize_t)size ? 0 : -1;
}

static int read_once(int fd, void *buffer, size_t size)
{
    ssize_t result;

    do {
        result = read(fd, buffer, size);
    } while (result < 0 && errno == EINTR);
    return result == (ssize_t)size ? 0 : -1;
}

static void close_pipe(int fds[2])
{
    if (fds[0] >= 0)
        close(fds[0]);
    if (fds[1] >= 0)
        close(fds[1]);
    fds[0] = -1;
    fds[1] = -1;
}

static int wait_atomic_at_least(_Atomic unsigned *value,
                                unsigned target, unsigned timeout_ms)
{
    unsigned elapsed;

    for (elapsed = 0; elapsed < timeout_ms; elapsed++) {
        if (atomic_load_explicit(value, memory_order_acquire) >= target)
            return 0;
        usleep(1000);
    }
    return -1;
}

static int wait_atomic_equal(_Atomic unsigned *value,
                             unsigned target, unsigned timeout_ms)
{
    unsigned elapsed;

    for (elapsed = 0; elapsed < timeout_ms; elapsed++) {
        unsigned observed = atomic_load_explicit(value, memory_order_acquire);

        if (observed == target)
            return 0;
        if (observed > target)
            return -1;
        usleep(1000);
    }
    return -1;
}

static _Atomic uint32_t g_cpu_seen[CPU_MASK_WORDS];

static void reset_cpu_seen(void)
{
    size_t i;

    for (i = 0; i < ARRAY_SIZE(g_cpu_seen); i++)
        atomic_store_explicit(&g_cpu_seen[i], 0, memory_order_relaxed);
}

static void mark_cpu_id(unsigned id)
{
    atomic_fetch_or_explicit(&g_cpu_seen[id / 32], 1u << (id % 32),
                             memory_order_relaxed);
}

static void mark_current_cpu(void)
{
    mark_cpu_id(current_apic_id());
}

static unsigned cpu_seen_count(void)
{
    unsigned count = 0;
    size_t i;

    for (i = 0; i < ARRAY_SIZE(g_cpu_seen); i++)
        count += (unsigned)__builtin_popcount(
            atomic_load_explicit(&g_cpu_seen[i], memory_order_relaxed));
    return count;
}

static int futex_wait_word(_Atomic int *word, int expected)
{
    return (int)syscall(SYS_futex, (int *)(void *)word,
                        FUTEX_WAIT | FUTEX_PRIVATE_FLAG, expected,
                        NULL, NULL, 0);
}

static int futex_wake_word(_Atomic int *word, int count)
{
    return (int)syscall(SYS_futex, (int *)(void *)word,
                        FUTEX_WAKE | FUTEX_PRIVATE_FLAG, count,
                        NULL, NULL, 0);
}

/* -------------------------------------------------------------------------- */
/* Repeated futex lost-wakeup handshake                                       */
/* -------------------------------------------------------------------------- */

#define FUTEX_HANDSHAKES 2000

static _Atomic int handshake_command;
static _Atomic int handshake_ack;
static _Atomic unsigned handshake_ready;
static _Atomic unsigned handshake_errors;
static _Atomic unsigned handshake_eagain;
static _Atomic unsigned handshake_waiter_apic_before;
static _Atomic unsigned handshake_waiter_apic_after;
static _Atomic unsigned handshake_waiter_blocked;
static _Atomic unsigned handshake_remote;

static int wait_for_futex_value(_Atomic int *word, int wanted, int *blocked)
{
    if (blocked != NULL)
        *blocked = 0;
    for (;;) {
        int observed = atomic_load_explicit(word, memory_order_acquire);
        int result;

        if (observed == wanted)
            return 0;
        if (observed > wanted)
            return -1;

        errno = 0;
        result = futex_wait_word(word, observed);
        if (result == 0) {
            if (blocked != NULL)
                *blocked = 1;
            continue;
        }
        if (errno == EAGAIN) {
            atomic_fetch_add_explicit(&handshake_eagain, 1,
                                      memory_order_relaxed);
            continue;
        }
        if (errno == EINTR)
            continue;
        return -1;
    }
}

static void *handshake_waiter(void *opaque)
{
    int iteration;

    (void)opaque;
    errno = 0;
    if (futex_wait_word(&handshake_command, -1) == -1 && errno == EAGAIN)
        atomic_fetch_add_explicit(&handshake_eagain, 1, memory_order_relaxed);
    else
        atomic_fetch_add_explicit(&handshake_errors, 1, memory_order_relaxed);

    atomic_store_explicit(&handshake_ready, 1, memory_order_release);
    for (iteration = 1; iteration <= FUTEX_HANDSHAKES; iteration++) {
        unsigned apic_before = current_apic_id();
        unsigned apic_after;
        int blocked;

        if (wait_for_futex_value(&handshake_command, iteration, &blocked) != 0) {
            atomic_fetch_add_explicit(&handshake_errors, 1,
                                      memory_order_relaxed);
            return NULL;
        }
        apic_after = current_apic_id();
        mark_cpu_id(apic_before);
        mark_cpu_id(apic_after);
        atomic_store_explicit(&handshake_waiter_apic_before, apic_before,
                              memory_order_relaxed);
        atomic_store_explicit(&handshake_waiter_apic_after, apic_after,
                              memory_order_relaxed);
        atomic_store_explicit(&handshake_waiter_blocked, blocked != 0,
                              memory_order_release);
        atomic_store_explicit(&handshake_ack, iteration, memory_order_release);
        if (futex_wake_word(&handshake_ack, 1) < 0) {
            atomic_fetch_add_explicit(&handshake_errors, 1,
                                      memory_order_relaxed);
            return NULL;
        }
    }
    return NULL;
}

static int test_futex_lost_wakeup_handshake(void)
{
    pthread_t waiter;
    int iteration;
    int create_result;

    reset_cpu_seen();
    atomic_store(&handshake_command, 0);
    atomic_store(&handshake_ack, 0);
    atomic_store(&handshake_ready, 0);
    atomic_store(&handshake_errors, 0);
    atomic_store(&handshake_eagain, 0);
    atomic_store(&handshake_waiter_apic_before, 0);
    atomic_store(&handshake_waiter_apic_after, 0);
    atomic_store(&handshake_waiter_blocked, 0);
    atomic_store(&handshake_remote, 0);

    create_result = pthread_create(&waiter, NULL, handshake_waiter, NULL);
    if (create_result != 0)
        return failf("pthread_create: %s", strerror(create_result));
    if (wait_atomic_at_least(&handshake_ready, 1, 3000) != 0)
        return failf("futex waiter did not become ready");

    errno = 0;
    if (futex_wait_word(&handshake_ack, -1) == -1 && errno == EAGAIN)
        atomic_fetch_add_explicit(&handshake_eagain, 1, memory_order_relaxed);
    else
        atomic_fetch_add_explicit(&handshake_errors, 1, memory_order_relaxed);

    for (iteration = 1; iteration <= FUTEX_HANDSHAKES; iteration++) {
        unsigned waker_before = current_apic_id();
        unsigned waker_after;
        unsigned waiter_before;
        unsigned waiter_after;
        unsigned waiter_blocked;

        atomic_store_explicit(&handshake_command, iteration,
                              memory_order_release);
        if (futex_wake_word(&handshake_command, 1) < 0)
            return failf("FUTEX_WAKE command failed: %s", strerror(errno));
        waker_after = current_apic_id();
        mark_cpu_id(waker_before);
        mark_cpu_id(waker_after);
        if (wait_for_futex_value(&handshake_ack, iteration, NULL) != 0)
            return failf("handshake stopped at iteration %d", iteration);

        waiter_before = atomic_load_explicit(&handshake_waiter_apic_before,
                                             memory_order_relaxed);
        waiter_after = atomic_load_explicit(&handshake_waiter_apic_after,
                                            memory_order_relaxed);
        waiter_blocked = atomic_load_explicit(&handshake_waiter_blocked,
                                              memory_order_acquire);
        if (waiter_blocked && waiter_before == waiter_after &&
            waker_before == waker_after && waiter_after != waker_after)
            atomic_store_explicit(&handshake_remote, 1,
                                  memory_order_relaxed);
    }

    if (pthread_join(waiter, NULL) != 0)
        return failf("pthread_join failed for futex waiter");
    if (atomic_load(&handshake_errors) != 0)
        return failf("futex handshake reported %u errors",
                     atomic_load(&handshake_errors));
    if (atomic_load(&handshake_eagain) < 2)
        return failf("FUTEX_WAIT EAGAIN paths were not exercised");
    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;
    if (!atomic_load(&handshake_remote))
        return failf("no handshake paired waiter and waker on different APIC IDs");
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Remote pipe read wake with directional pipes                               */
/* -------------------------------------------------------------------------- */

#define PIPE_WAKE_ROUNDS 192

static int pipe_wake_control[2];
static int pipe_wake_data[2];
static _Atomic unsigned pipe_wake_reader_apic_before;
static _Atomic unsigned pipe_wake_reader_apic_after;
static _Atomic unsigned pipe_wake_entered;
static _Atomic unsigned pipe_wake_completed;
static _Atomic unsigned pipe_wake_checked;
static _Atomic unsigned pipe_wake_remote;
static _Atomic unsigned pipe_wake_errors;

static void *pipe_wake_reader(void *opaque)
{
    unsigned iteration;

    (void)opaque;
    for (iteration = 0; iteration < PIPE_WAKE_ROUNDS; iteration++) {
        unsigned generation = iteration + 1;
        unsigned apic_before;
        unsigned apic_after;
        unsigned char ready = (unsigned char)iteration;
        unsigned char token = 0;
        unsigned char expected = (unsigned char)(iteration * 37u + 11u);
        int token_ok;

        if (full_write(pipe_wake_control[1], &ready, 1) != 0) {
            atomic_fetch_add_explicit(&pipe_wake_errors, 1,
                                      memory_order_relaxed);
            return NULL;
        }
        apic_before = current_apic_id();
        mark_cpu_id(apic_before);
        atomic_store_explicit(&pipe_wake_reader_apic_before, apic_before,
                              memory_order_relaxed);
        atomic_store_explicit(&pipe_wake_entered, generation,
                              memory_order_release);
        if (full_read(pipe_wake_data[0], &token, 1) != 0) {
            atomic_fetch_add_explicit(&pipe_wake_errors, 1,
                                      memory_order_relaxed);
            return NULL;
        }
        apic_after = current_apic_id();
        mark_cpu_id(apic_after);
        atomic_store_explicit(&pipe_wake_reader_apic_after, apic_after,
                              memory_order_relaxed);
        token_ok = token == expected;
        if (!token_ok)
            atomic_fetch_add_explicit(&pipe_wake_errors, 1,
                                      memory_order_relaxed);
        atomic_store_explicit(&pipe_wake_completed, generation,
                              memory_order_release);
        while (atomic_load_explicit(&pipe_wake_checked,
                                    memory_order_acquire) < generation)
            cpu_relax();
        if (!token_ok)
            return NULL;
    }
    return NULL;
}

static int test_remote_pipe_read_wake(void)
{
    pthread_t reader;
    unsigned iteration;
    int create_result;

    pipe_wake_control[0] = pipe_wake_control[1] = -1;
    pipe_wake_data[0] = pipe_wake_data[1] = -1;
    if (pipe(pipe_wake_control) != 0)
        return failf("control pipe: %s", strerror(errno));
    if (pipe(pipe_wake_data) != 0) {
        close_pipe(pipe_wake_control);
        return failf("data pipe: %s", strerror(errno));
    }

    reset_cpu_seen();
    atomic_store(&pipe_wake_reader_apic_before, 0);
    atomic_store(&pipe_wake_reader_apic_after, 0);
    atomic_store(&pipe_wake_entered, 0);
    atomic_store(&pipe_wake_completed, 0);
    atomic_store(&pipe_wake_checked, 0);
    atomic_store(&pipe_wake_remote, 0);
    atomic_store(&pipe_wake_errors, 0);
    create_result = pthread_create(&reader, NULL, pipe_wake_reader, NULL);
    if (create_result != 0) {
        close_pipe(pipe_wake_control);
        close_pipe(pipe_wake_data);
        return failf("pthread_create: %s", strerror(create_result));
    }

    for (iteration = 0; iteration < PIPE_WAKE_ROUNDS; iteration++) {
        unsigned char ready;
        unsigned char token = (unsigned char)(iteration * 37u + 11u);
        unsigned generation = iteration + 1;
        unsigned writer_before;
        unsigned writer_after;
        unsigned reader_before;
        unsigned reader_after;

        if (full_read(pipe_wake_control[0], &ready, 1) != 0)
            return failf("control pipe read failed at round %u", iteration);
        if (ready != (unsigned char)iteration)
            return failf("control token mismatch at round %u", iteration);
        if (wait_atomic_at_least(&pipe_wake_entered, generation, 3000) != 0)
            return failf("pipe reader did not reach read at round %u", iteration);

        /* The marker is immediately before read; this delay narrows, but cannot
           remove, the unavoidable marker-to-syscall scheduling window. */
        usleep(1000);
        writer_before = current_apic_id();
        if (full_write(pipe_wake_data[1], &token, 1) != 0)
            return failf("data pipe write failed at round %u", iteration);
        writer_after = current_apic_id();
        mark_cpu_id(writer_before);
        mark_cpu_id(writer_after);
        if (wait_atomic_at_least(&pipe_wake_completed, generation, 3000) != 0)
            return failf("pipe reader made no progress at round %u", iteration);

        reader_before = atomic_load_explicit(&pipe_wake_reader_apic_before,
                                             memory_order_relaxed);
        reader_after = atomic_load_explicit(&pipe_wake_reader_apic_after,
                                            memory_order_acquire);
        if (reader_before == reader_after && writer_before == writer_after &&
            reader_after != writer_after)
            atomic_store_explicit(&pipe_wake_remote, 1,
                                  memory_order_relaxed);
        atomic_store_explicit(&pipe_wake_checked, generation,
                              memory_order_release);
    }

    if (pthread_join(reader, NULL) != 0)
        return failf("pthread_join failed for pipe reader");
    close_pipe(pipe_wake_control);
    close_pipe(pipe_wake_data);

    if (atomic_load(&pipe_wake_errors) != 0)
        return failf("pipe reader reported an I/O or token error");
    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;
    if (!atomic_load(&pipe_wake_remote))
        return failf("no pipe wake paired reader and writer on different APIC IDs");
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Thread-directed masked signal pending/unblock                              */
/* -------------------------------------------------------------------------- */

#define SIGNAL_ROUNDS 48

static int signal_commands[2];
static int signal_events[2];
static _Atomic unsigned signal_sender_apic_before;
static _Atomic unsigned signal_sender_apic_after;
static _Atomic unsigned signal_remote;
static _Atomic unsigned signal_errors;
static _Atomic int signal_handler_tid;
static _Atomic unsigned signal_handler_apic_before;
static _Atomic unsigned signal_handler_apic_after;
static _Atomic unsigned signal_handler_hits;

static void directed_signal_handler(int signo)
{
    unsigned apic_before;

    (void)signo;
    apic_before = current_apic_id();
    atomic_store_explicit(&signal_handler_apic_before, apic_before,
                          memory_order_relaxed);
    atomic_store_explicit(&signal_handler_tid, raw_gettid(),
                          memory_order_relaxed);
    atomic_fetch_add_explicit(&signal_handler_hits, 1, memory_order_relaxed);
    atomic_store_explicit(&signal_handler_apic_after, current_apic_id(),
                          memory_order_release);
}

static void *directed_signal_worker(void *opaque)
{
    sigset_t blocked;
    pid_t tid = raw_gettid();
    unsigned iteration;

    (void)opaque;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGUSR1);

    for (iteration = 0; iteration < SIGNAL_ROUNDS; iteration++) {
        sigset_t pending;
        unsigned sender_before;
        unsigned sender_after;
        unsigned handler_before;
        unsigned handler_after;
        unsigned char event = 'R';
        unsigned char command;
        int mask_result;

        if (full_write(signal_events[1], &event, 1) != 0 ||
            full_read(signal_commands[0], &command, 1) != 0 ||
            command != 'C') {
            atomic_fetch_add(&signal_errors, 1);
            return NULL;
        }

        sigemptyset(&pending);
        event = sigpending(&pending) == 0 &&
                        sigismember(&pending, SIGUSR1) == 1
                    ? 'P'
                    : 'N';
        if (full_write(signal_events[1], &event, 1) != 0 ||
            full_read(signal_commands[0], &command, 1) != 0 ||
            command != 'U') {
            atomic_fetch_add(&signal_errors, 1);
            return NULL;
        }

        mask_result = pthread_sigmask(SIG_UNBLOCK, &blocked, NULL);
        sender_before = atomic_load_explicit(&signal_sender_apic_before,
                                             memory_order_relaxed);
        sender_after = atomic_load_explicit(&signal_sender_apic_after,
                                            memory_order_acquire);
        handler_before = atomic_load_explicit(&signal_handler_apic_before,
                                              memory_order_relaxed);
        handler_after = atomic_load_explicit(&signal_handler_apic_after,
                                             memory_order_acquire);
        mark_cpu_id(handler_before);
        mark_cpu_id(handler_after);
        if (sender_before == sender_after && handler_before == handler_after &&
            sender_after != handler_after)
            atomic_store_explicit(&signal_remote, 1, memory_order_relaxed);
        if (mask_result != 0 ||
            atomic_load_explicit(&signal_handler_hits,
                                 memory_order_acquire) != iteration + 1 ||
            atomic_load_explicit(&signal_handler_tid,
                                 memory_order_relaxed) != tid) {
            atomic_fetch_add(&signal_errors, 1);
            event = 'N';
        } else {
            event = 'H';
        }

        mask_result = pthread_sigmask(SIG_BLOCK, &blocked, NULL);
        if (mask_result != 0)
            atomic_fetch_add(&signal_errors, 1);
        if (full_write(signal_events[1], &event, 1) != 0)
            return NULL;
    }
    return NULL;
}

static int test_directed_masked_signal(void)
{
    struct sigaction action;
    sigset_t blocked;
    sigset_t old_mask;
    pthread_t worker;
    unsigned iteration;
    int result;

    signal_commands[0] = signal_commands[1] = -1;
    signal_events[0] = signal_events[1] = -1;
    if (pipe(signal_commands) != 0)
        return failf("signal command pipe: %s", strerror(errno));
    if (pipe(signal_events) != 0) {
        close_pipe(signal_commands);
        return failf("signal event pipe: %s", strerror(errno));
    }

    memset(&action, 0, sizeof(action));
    action.sa_handler = directed_signal_handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, NULL) != 0)
        return failf("sigaction: %s", strerror(errno));

    sigemptyset(&blocked);
    sigaddset(&blocked, SIGUSR1);
    result = pthread_sigmask(SIG_BLOCK, &blocked, &old_mask);
    if (result != 0)
        return failf("pthread_sigmask: %s", strerror(result));

    reset_cpu_seen();
    atomic_store(&signal_sender_apic_before, 0);
    atomic_store(&signal_sender_apic_after, 0);
    atomic_store(&signal_remote, 0);
    atomic_store(&signal_errors, 0);
    atomic_store(&signal_handler_tid, 0);
    atomic_store(&signal_handler_apic_before, 0);
    atomic_store(&signal_handler_apic_after, 0);
    atomic_store(&signal_handler_hits, 0);

    result = pthread_create(&worker, NULL, directed_signal_worker, NULL);
    if (result != 0) {
        pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
        close_pipe(signal_commands);
        close_pipe(signal_events);
        return failf("pthread_create: %s", strerror(result));
    }

    for (iteration = 0; iteration < SIGNAL_ROUNDS; iteration++) {
        unsigned char event;
        unsigned char command;
        unsigned sender_before;
        unsigned sender_after;

        if (full_read(signal_events[0], &event, 1) != 0 || event != 'R')
            return failf("signal worker readiness failed at round %u", iteration);
        sender_before = current_apic_id();
        atomic_store_explicit(&signal_sender_apic_before, sender_before,
                              memory_order_relaxed);
        result = pthread_kill(worker, SIGUSR1);
        sender_after = current_apic_id();
        atomic_store_explicit(&signal_sender_apic_after, sender_after,
                              memory_order_release);
        mark_cpu_id(sender_before);
        mark_cpu_id(sender_after);
        if (result != 0)
            return failf("pthread_kill round %u: %s", iteration,
                         strerror(result));
        command = 'C';
        if (full_write(signal_commands[1], &command, 1) != 0 ||
            full_read(signal_events[0], &event, 1) != 0 || event != 'P')
            return failf("SIGUSR1 was not pending while masked at round %u",
                         iteration);

        command = 'U';
        if (full_write(signal_commands[1], &command, 1) != 0 ||
            full_read(signal_events[0], &event, 1) != 0 || event != 'H')
            return failf("signal delivery/TID verification failed at round %u",
                         iteration);
    }

    result = pthread_join(worker, NULL);
    pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
    close_pipe(signal_commands);
    close_pipe(signal_events);
    if (result != 0)
        return failf("pthread_join failed for signal worker");
    if (atomic_load(&signal_errors) != 0 ||
        atomic_load(&signal_handler_hits) != SIGNAL_ROUNDS)
        return failf("signal worker reported %u errors and %u handlers",
                     atomic_load(&signal_errors),
                     atomic_load(&signal_handler_hits));
    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;
    if (!atomic_load(&signal_remote))
        return failf("no directed signal crossed observed APIC IDs");
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Contended pthread mutex exact counter and progress                         */
/* -------------------------------------------------------------------------- */

#define MUTEX_WORKERS 12
#define MUTEX_ITERATIONS 10000

static pthread_mutex_t counter_mutex;
static uint64_t mutex_counter;
static unsigned mutex_last_owner;
static unsigned mutex_owner_changes;
static _Atomic unsigned mutex_ready;
static _Atomic unsigned mutex_start;
static _Atomic unsigned mutex_first_acquisitions;
static _Atomic unsigned mutex_target;
static _Atomic unsigned mutex_errors;
static _Atomic unsigned mutex_progress[MUTEX_WORKERS];

static void mutex_count_once(unsigned index)
{
    if (pthread_mutex_lock(&counter_mutex) != 0) {
        atomic_fetch_add(&mutex_errors, 1);
        return;
    }
    mutex_counter++;
    if (mutex_last_owner != index) {
        mutex_last_owner = index;
        mutex_owner_changes++;
    }
    if (pthread_mutex_unlock(&counter_mutex) != 0)
        atomic_fetch_add(&mutex_errors, 1);
    atomic_fetch_add_explicit(&mutex_progress[index], 1,
                              memory_order_relaxed);
}

static void *mutex_counter_worker(void *opaque)
{
    unsigned index = (unsigned)(uintptr_t)opaque;
    unsigned iteration;

    atomic_fetch_add_explicit(&mutex_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&mutex_start, memory_order_acquire))
        cpu_relax();

    mutex_count_once(index);
    atomic_fetch_add_explicit(&mutex_first_acquisitions, 1,
                              memory_order_release);
    while (atomic_load_explicit(&mutex_first_acquisitions,
                                memory_order_acquire) <
           atomic_load_explicit(&mutex_target, memory_order_acquire))
        cpu_relax();

    for (iteration = 0; iteration < MUTEX_ITERATIONS; iteration++)
        mutex_count_once(index);
    return NULL;
}

static int test_contended_pthread_mutex(void)
{
    pthread_t workers[MUTEX_WORKERS];
    unsigned created = 0;
    unsigned index;
    int result;
    int failed_create = 0;
    uint64_t expected =
        (uint64_t)MUTEX_WORKERS * (MUTEX_ITERATIONS + 1u);

    result = pthread_mutex_init(&counter_mutex, NULL);
    if (result != 0)
        return failf("pthread_mutex_init: %s", strerror(result));
    mutex_counter = 0;
    mutex_last_owner = UINT_MAX;
    mutex_owner_changes = 0;
    atomic_store(&mutex_ready, 0);
    atomic_store(&mutex_start, 0);
    atomic_store(&mutex_first_acquisitions, 0);
    atomic_store(&mutex_target, 0);
    atomic_store(&mutex_errors, 0);
    for (index = 0; index < MUTEX_WORKERS; index++)
        atomic_store(&mutex_progress[index], 0);

    for (index = 0; index < MUTEX_WORKERS; index++) {
        result = pthread_create(&workers[index], NULL, mutex_counter_worker,
                                (void *)(uintptr_t)index);
        if (result != 0) {
            failed_create = result;
            break;
        }
        created++;
    }
    atomic_store_explicit(&mutex_target, created, memory_order_release);
    atomic_store_explicit(&mutex_start, 1, memory_order_release);
    for (index = 0; index < created; index++)
        pthread_join(workers[index], NULL);

    if (failed_create != 0) {
        pthread_mutex_destroy(&counter_mutex);
        return failf("pthread_create stopped at %u/%u: %s", created,
                     MUTEX_WORKERS, strerror(failed_create));
    }
    if (mutex_counter != expected) {
        pthread_mutex_destroy(&counter_mutex);
        return failf("mutex counter is %llu, expected %llu",
                     (unsigned long long)mutex_counter,
                     (unsigned long long)expected);
    }
    for (index = 0; index < MUTEX_WORKERS; index++) {
        if (atomic_load(&mutex_progress[index]) != MUTEX_ITERATIONS + 1u) {
            pthread_mutex_destroy(&counter_mutex);
            return failf("mutex worker %u made only %u acquisitions", index,
                         atomic_load(&mutex_progress[index]));
        }
    }
    if (atomic_load(&mutex_errors) != 0 ||
        mutex_owner_changes < MUTEX_WORKERS) {
        pthread_mutex_destroy(&counter_mutex);
        return failf("mutex errors=%u owner changes=%u",
                     atomic_load(&mutex_errors), mutex_owner_changes);
    }
    result = pthread_mutex_destroy(&counter_mutex);
    if (result != 0)
        return failf("pthread_mutex_destroy: %s", strerror(result));
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Mixed CPU-bound and sleeper scheduler fairness                             */
/* -------------------------------------------------------------------------- */

#define SCHED_CPU_WORKERS 8
#define SCHED_SLEEP_WORKERS 8
#define SCHED_WORKERS (SCHED_CPU_WORKERS + SCHED_SLEEP_WORKERS)

struct scheduler_arg {
    unsigned index;
    int sleeper;
};

static _Atomic unsigned scheduler_ready;
static _Atomic unsigned scheduler_start;
static _Atomic unsigned scheduler_stop;
static _Atomic unsigned scheduler_errors;
static _Atomic uint64_t scheduler_progress[SCHED_WORKERS];

static void *scheduler_worker(void *opaque)
{
    struct scheduler_arg *arg = opaque;
    uint64_t progress = 0;

    atomic_fetch_add_explicit(&scheduler_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&scheduler_start, memory_order_acquire))
        cpu_relax();

    if (arg->sleeper) {
        const struct timespec delay = { .tv_sec = 0, .tv_nsec = 2000000 };

        while (!atomic_load_explicit(&scheduler_stop, memory_order_acquire)) {
            if (nanosleep(&delay, NULL) != 0 && errno != EINTR) {
                atomic_fetch_add(&scheduler_errors, 1);
                break;
            }
            progress++;
            mark_current_cpu();
        }
    } else {
        while (!atomic_load_explicit(&scheduler_stop, memory_order_acquire)) {
            progress++;
            if ((progress & 0x3ffu) == 0)
                mark_current_cpu();
        }
        mark_current_cpu();
    }
    atomic_store_explicit(&scheduler_progress[arg->index], progress,
                          memory_order_release);
    return NULL;
}

static int test_scheduler_mixed_fairness(void)
{
    pthread_t workers[SCHED_WORKERS];
    struct scheduler_arg args[SCHED_WORKERS];
    unsigned created = 0;
    unsigned index;
    int create_error = 0;

    reset_cpu_seen();
    atomic_store(&scheduler_ready, 0);
    atomic_store(&scheduler_start, 0);
    atomic_store(&scheduler_stop, 0);
    atomic_store(&scheduler_errors, 0);
    for (index = 0; index < SCHED_WORKERS; index++) {
        args[index].index = index;
        args[index].sleeper = index >= SCHED_CPU_WORKERS;
        atomic_store(&scheduler_progress[index], 0);
        create_error = pthread_create(&workers[index], NULL, scheduler_worker,
                                      &args[index]);
        if (create_error != 0)
            break;
        created++;
    }
    if (created != SCHED_WORKERS) {
        atomic_store(&scheduler_start, 1);
        atomic_store(&scheduler_stop, 1);
        for (index = 0; index < created; index++)
            pthread_join(workers[index], NULL);
        return failf("pthread_create stopped at %u/%u: %s", created,
                     SCHED_WORKERS, strerror(create_error));
    }
    if (wait_atomic_at_least(&scheduler_ready, SCHED_WORKERS, 3000) != 0)
        return failf("scheduler workers did not all become runnable");

    atomic_store_explicit(&scheduler_start, 1, memory_order_release);
    usleep(700000);
    atomic_store_explicit(&scheduler_stop, 1, memory_order_release);
    for (index = 0; index < SCHED_WORKERS; index++) {
        if (pthread_join(workers[index], NULL) != 0)
            return failf("pthread_join failed for scheduler worker %u", index);
    }

    if (atomic_load(&scheduler_errors) != 0)
        return failf("scheduler sleepers reported %u nanosleep errors",
                     atomic_load(&scheduler_errors));
    for (index = 0; index < SCHED_CPU_WORKERS; index++) {
        if (atomic_load(&scheduler_progress[index]) < 1000)
            return failf("CPU-bound worker %u was starved", index);
    }
    for (; index < SCHED_WORKERS; index++) {
        if (atomic_load(&scheduler_progress[index]) < 3)
            return failf("sleeper worker %u was starved", index);
    }
    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Concurrent shared TaskFiles pipe allocation                                */
/* -------------------------------------------------------------------------- */

#define PIPE_ALLOC_WORKERS 12
#define PIPE_ALLOC_ROUNDS 4

struct pipe_alloc_arg {
    int fds[2];
    int error_number;
};

struct pipe_token {
    uint32_t magic;
    uint32_t round;
    uint32_t worker;
    uint32_t inverse;
};

static struct pipe_alloc_arg pipe_alloc_args[PIPE_ALLOC_WORKERS];
static _Atomic unsigned pipe_alloc_ready;
static _Atomic unsigned pipe_alloc_start;

static void *pipe_alloc_worker(void *opaque)
{
    struct pipe_alloc_arg *arg = opaque;

    atomic_fetch_add_explicit(&pipe_alloc_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&pipe_alloc_start, memory_order_acquire))
        cpu_relax();
    errno = 0;
    if (pipe2(arg->fds, O_NONBLOCK) != 0)
        arg->error_number = errno;
    return NULL;
}

static void close_unique_allocated_fds(unsigned count)
{
    int closed[PIPE_ALLOC_WORKERS * 2];
    unsigned closed_count = 0;
    unsigned index;
    unsigned endpoint;

    for (index = 0; index < count; index++) {
        for (endpoint = 0; endpoint < 2; endpoint++) {
            int fd = pipe_alloc_args[index].fds[endpoint];
            unsigned previous;
            int already_closed = 0;

            if (fd < 0)
                continue;
            for (previous = 0; previous < closed_count; previous++) {
                if (closed[previous] == fd) {
                    already_closed = 1;
                    break;
                }
            }
            if (!already_closed) {
                close(fd);
                closed[closed_count++] = fd;
            }
            pipe_alloc_args[index].fds[endpoint] = -1;
        }
    }
}

static int test_concurrent_pipe_allocation(void)
{
    pthread_t workers[PIPE_ALLOC_WORKERS];
    unsigned round;

    for (round = 0; round < PIPE_ALLOC_ROUNDS; round++) {
        unsigned created = 0;
        unsigned index;
        unsigned endpoint;
        int create_error = 0;

        atomic_store(&pipe_alloc_ready, 0);
        atomic_store(&pipe_alloc_start, 0);
        for (index = 0; index < PIPE_ALLOC_WORKERS; index++) {
            pipe_alloc_args[index].fds[0] = -1;
            pipe_alloc_args[index].fds[1] = -1;
            pipe_alloc_args[index].error_number = 0;
            create_error = pthread_create(&workers[index], NULL,
                                          pipe_alloc_worker,
                                          &pipe_alloc_args[index]);
            if (create_error != 0)
                break;
            created++;
        }
        if (created != PIPE_ALLOC_WORKERS) {
            atomic_store_explicit(&pipe_alloc_start, 1, memory_order_release);
            for (index = 0; index < created; index++)
                pthread_join(workers[index], NULL);
            close_unique_allocated_fds(created);
            return failf("pipe allocator thread creation stopped at %u: %s",
                         created, strerror(create_error));
        }
        if (wait_atomic_equal(&pipe_alloc_ready, PIPE_ALLOC_WORKERS, 3000) != 0) {
            atomic_store_explicit(&pipe_alloc_start, 1, memory_order_release);
            for (index = 0; index < created; index++)
                pthread_join(workers[index], NULL);
            close_unique_allocated_fds(created);
            return failf("pipe allocator workers did not reach start barrier");
        }

        /* Intentional kernel stress: all pthreads share TaskFiles and call
           pipe2 concurrently without a userspace lock. */
        atomic_store_explicit(&pipe_alloc_start, 1, memory_order_release);
        for (index = 0; index < created; index++)
            pthread_join(workers[index], NULL);

        for (index = 0; index < PIPE_ALLOC_WORKERS; index++) {
            if (pipe_alloc_args[index].error_number != 0) {
                int saved = pipe_alloc_args[index].error_number;

                close_unique_allocated_fds(PIPE_ALLOC_WORKERS);
                return failf("pipe2 worker %u round %u: %s", index, round,
                             strerror(saved));
            }
            if (pipe_alloc_args[index].fds[0] < 0 ||
                pipe_alloc_args[index].fds[1] < 0 ||
                pipe_alloc_args[index].fds[0] ==
                    pipe_alloc_args[index].fds[1]) {
                close_unique_allocated_fds(PIPE_ALLOC_WORKERS);
                return failf("invalid pipe pair from worker %u round %u",
                             index, round);
            }
        }

        for (index = 0; index < PIPE_ALLOC_WORKERS; index++) {
            for (endpoint = 0; endpoint < 2; endpoint++) {
                int fd = pipe_alloc_args[index].fds[endpoint];
                unsigned other;
                unsigned other_endpoint;

                for (other = 0; other <= index; other++) {
                    unsigned limit = other == index ? endpoint : 2;

                    for (other_endpoint = 0; other_endpoint < limit;
                         other_endpoint++) {
                        if (pipe_alloc_args[other].fds[other_endpoint] == fd) {
                            close_unique_allocated_fds(PIPE_ALLOC_WORKERS);
                            return failf("duplicate fd %d in allocation round %u",
                                         fd, round);
                        }
                    }
                }
            }
        }

        /* Write every nonblocking pipe first, so a wrong pairing cannot hang. */
        for (index = 0; index < PIPE_ALLOC_WORKERS; index++) {
            struct pipe_token token = {
                .magic = 0x50495045u,
                .round = round,
                .worker = index,
                .inverse = ~(round * 257u + index),
            };

            if (write_once(pipe_alloc_args[index].fds[1], &token,
                           sizeof(token)) != 0) {
                close_unique_allocated_fds(PIPE_ALLOC_WORKERS);
                return failf("pipe token write failed for worker %u round %u",
                             index, round);
            }
        }
        for (index = 0; index < PIPE_ALLOC_WORKERS; index++) {
            struct pipe_token token;
            struct pipe_token expected = {
                .magic = 0x50495045u,
                .round = round,
                .worker = index,
                .inverse = ~(round * 257u + index),
            };

            memset(&token, 0, sizeof(token));
            if (read_once(pipe_alloc_args[index].fds[0], &token,
                          sizeof(token)) != 0 ||
                memcmp(&token, &expected, sizeof(token)) != 0) {
                close_unique_allocated_fds(PIPE_ALLOC_WORKERS);
                return failf("pipe token pairing failed for worker %u round %u",
                             index, round);
            }
        }
        close_unique_allocated_fds(PIPE_ALLOC_WORKERS);
    }
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Concurrent waitpid(-1) exact-once reaping                                  */
/* -------------------------------------------------------------------------- */

#define WAIT_CHILDREN 8
#define WAIT_THREADS 2

static pid_t wait_children[WAIT_CHILDREN];
static _Atomic unsigned wait_start;
static _Atomic unsigned wait_total;
static _Atomic unsigned wait_echild;
static _Atomic unsigned wait_errors;
static _Atomic unsigned wait_reaped[WAIT_CHILDREN];

static void *wait_any_worker(void *opaque)
{
    (void)opaque;
    while (!atomic_load_explicit(&wait_start, memory_order_acquire))
        cpu_relax();

    for (;;) {
        int status = 0;
        pid_t result;
        unsigned index;

        if (atomic_load_explicit(&wait_total, memory_order_acquire) >=
            WAIT_CHILDREN)
            return NULL;
        do {
            errno = 0;
            result = waitpid(-1, &status, 0);
        } while (result < 0 && errno == EINTR);

        if (result < 0) {
            if (errno == ECHILD)
                atomic_fetch_add_explicit(&wait_echild, 1,
                                          memory_order_relaxed);
            else
                atomic_fetch_add_explicit(&wait_errors, 1,
                                          memory_order_relaxed);
            return NULL;
        }

        for (index = 0; index < WAIT_CHILDREN; index++) {
            if (wait_children[index] == result)
                break;
        }
        if (index == WAIT_CHILDREN) {
            atomic_fetch_add_explicit(&wait_errors, 1, memory_order_relaxed);
        } else {
            /* Record ownership immediately, even when status validation fails,
               so cleanup can never signal a PID that has already been reaped. */
            if (atomic_fetch_add_explicit(&wait_reaped[index], 1,
                                          memory_order_relaxed) != 0)
                atomic_fetch_add_explicit(&wait_errors, 1,
                                          memory_order_relaxed);
            if (!WIFEXITED(status) ||
                WEXITSTATUS(status) != (int)(60u + index))
                atomic_fetch_add_explicit(&wait_errors, 1,
                                          memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&wait_total, 1, memory_order_release);
    }
}

static void cleanup_wait_children(void)
{
    unsigned index;

    for (index = 0; index < WAIT_CHILDREN; index++) {
        int status;
        pid_t result;

        if (wait_children[index] <= 0 || atomic_load(&wait_reaped[index]) != 0)
            continue;
        kill(wait_children[index], SIGKILL);
        do {
            result = waitpid(wait_children[index], &status, 0);
        } while (result < 0 && errno == EINTR);
        if (result == wait_children[index])
            atomic_store(&wait_reaped[index], 1);
    }
}

static int reap_wait_children_as_leader(void)
{
    unsigned index;
    int failed = 0;

    for (index = 0; index < WAIT_CHILDREN; index++) {
        int status = 0;
        pid_t result;

        if (wait_children[index] <= 0 || atomic_load(&wait_reaped[index]) != 0)
            continue;
        do {
            result = waitpid(wait_children[index], &status, 0);
        } while (result < 0 && errno == EINTR);
        if (result == wait_children[index]) {
            atomic_store(&wait_reaped[index], 1);
            if (!WIFEXITED(status) ||
                WEXITSTATUS(status) != (int)(60u + index))
                failed = 1;
        } else {
            failed = 1;
        }
    }
    return failed ? -1 : 0;
}

static int test_concurrent_waitpid_any(void)
{
    pthread_t waiters[WAIT_THREADS];
    unsigned index;
    unsigned created = 0;
    int create_error = 0;
    int join_error = 0;

    atomic_store(&wait_start, 0);
    atomic_store(&wait_total, 0);
    atomic_store(&wait_echild, 0);
    atomic_store(&wait_errors, 0);
    for (index = 0; index < WAIT_CHILDREN; index++) {
        atomic_store(&wait_reaped[index], 0);
        wait_children[index] = -1;
    }
    for (index = 0; index < WAIT_CHILDREN; index++) {
        wait_children[index] = fork();
        if (wait_children[index] == 0) {
            usleep(20000 + index * 4000);
            _exit((int)(60u + index));
        }
        if (wait_children[index] < 0) {
            int saved_errno = errno;

            wait_children[index] = -1;
            cleanup_wait_children();
            return failf("fork child %u: %s", index, strerror(saved_errno));
        }
    }

    for (index = 0; index < WAIT_THREADS; index++) {
        create_error = pthread_create(&waiters[index], NULL, wait_any_worker,
                                      NULL);
        if (create_error != 0)
            break;
        created++;
    }
    atomic_store_explicit(&wait_start, 1, memory_order_release);
    for (index = 0; index < created; index++) {
        int result = pthread_join(waiters[index], NULL);

        if (result != 0 && join_error == 0)
            join_error = result;
    }
    if (created != WAIT_THREADS) {
        cleanup_wait_children();
        return failf("waiter pthread_create: %s", strerror(create_error));
    }
    if (join_error != 0) {
        cleanup_wait_children();
        return failf("waiter pthread_join: %s", strerror(join_error));
    }

    if (atomic_load(&wait_total) == 0 &&
        atomic_load(&wait_echild) == WAIT_THREADS) {
        if (reap_wait_children_as_leader() != 0) {
            cleanup_wait_children();
            return failf("leader could not reap after pthread ECHILD");
        }
        return TEST_SKIP;
    }

    if (atomic_load(&wait_total) != WAIT_CHILDREN ||
        atomic_load(&wait_errors) != 0) {
        unsigned total = atomic_load(&wait_total);
        unsigned errors = atomic_load(&wait_errors);

        cleanup_wait_children();
        return failf("waiters reaped %u/%u children with %u errors", total,
                     WAIT_CHILDREN, errors);
    }
    for (index = 0; index < WAIT_CHILDREN; index++) {
        if (atomic_load(&wait_reaped[index]) != 1) {
            cleanup_wait_children();
            return failf("child %u reap count is %u", index,
                         atomic_load(&wait_reaped[index]));
        }
    }
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* exit_group tears down threads blocked in unrelated wait paths              */
/* -------------------------------------------------------------------------- */

static _Atomic unsigned exit_block_errors;
static _Atomic int exit_block_futex;
static _Atomic unsigned exit_futex_entered;
static _Atomic unsigned exit_futex_returns;
static _Atomic unsigned exit_pipe_entered;
static _Atomic unsigned exit_pipe_returns;
static _Atomic unsigned exit_sleep_entered;
static _Atomic unsigned exit_sleep_returns;
static int exit_block_pipe[2];

static void *exit_futex_waiter(void *opaque)
{
    (void)opaque;
    for (;;) {
        int result;

        atomic_fetch_add_explicit(&exit_futex_entered, 1,
                                  memory_order_release);
        result = futex_wait_word(&exit_block_futex, 0);
        if (result == 0) {
            atomic_fetch_add_explicit(&exit_futex_returns, 1,
                                      memory_order_release);
            continue;
        }
        if (result < 0 && errno != EAGAIN && errno != EINTR)
            atomic_fetch_add(&exit_block_errors, 1);
    }
}

static void *exit_pipe_waiter(void *opaque)
{
    (void)opaque;
    for (;;) {
        unsigned char byte;

        atomic_fetch_add_explicit(&exit_pipe_entered, 1,
                                  memory_order_release);
        if (full_read(exit_block_pipe[0], &byte, 1) != 0) {
            atomic_fetch_add(&exit_block_errors, 1);
            return NULL;
        }
        if (byte != 0xa5)
            atomic_fetch_add(&exit_block_errors, 1);
        atomic_fetch_add_explicit(&exit_pipe_returns, 1,
                                  memory_order_release);
    }
}

static void *exit_sleep_waiter(void *opaque)
{
    const struct timespec probe = { .tv_sec = 0, .tv_nsec = 10000000 };
    const struct timespec blocked = { .tv_sec = 60, .tv_nsec = 0 };

    (void)opaque;
    atomic_fetch_add_explicit(&exit_sleep_entered, 1, memory_order_release);
    if (nanosleep(&probe, NULL) == 0)
        atomic_fetch_add_explicit(&exit_sleep_returns, 1,
                                  memory_order_release);
    else if (errno != EINTR)
        atomic_fetch_add(&exit_block_errors, 1);
    for (;;) {
        atomic_fetch_add_explicit(&exit_sleep_entered, 1,
                                  memory_order_release);
        if (nanosleep(&blocked, NULL) == 0)
            atomic_fetch_add_explicit(&exit_sleep_returns, 1,
                                      memory_order_release);
        else if (errno != EINTR)
            atomic_fetch_add(&exit_block_errors, 1);
    }
}

static int test_exit_group_blocked_threads(void)
{
    pid_t child;
    int status = 0;
    pid_t result;

    exit_block_pipe[0] = exit_block_pipe[1] = -1;
    if (pipe(exit_block_pipe) != 0)
        return failf("exit_group pipe: %s", strerror(errno));
    atomic_store(&exit_block_errors, 0);
    atomic_store(&exit_block_futex, 0);
    atomic_store(&exit_futex_entered, 0);
    atomic_store(&exit_futex_returns, 0);
    atomic_store(&exit_pipe_entered, 0);
    atomic_store(&exit_pipe_returns, 0);
    atomic_store(&exit_sleep_entered, 0);
    atomic_store(&exit_sleep_returns, 0);

    child = fork();
    if (child < 0) {
        close_pipe(exit_block_pipe);
        return failf("exit_group inner fork: %s", strerror(errno));
    }
    if (child == 0) {
        pthread_t futex_thread;
        pthread_t pipe_thread;
        pthread_t sleep_thread;

        if (pthread_create(&futex_thread, NULL, exit_futex_waiter, NULL) != 0 ||
            pthread_create(&pipe_thread, NULL, exit_pipe_waiter, NULL) != 0 ||
            pthread_create(&sleep_thread, NULL, exit_sleep_waiter, NULL) != 0)
            _exit(120);
        if (wait_atomic_at_least(&exit_futex_entered, 1, 3000) != 0 ||
            wait_atomic_at_least(&exit_pipe_entered, 1, 3000) != 0 ||
            wait_atomic_at_least(&exit_sleep_entered, 1, 3000) != 0)
            _exit(121);

        /* Exercise each syscall path through a completed operation, then wait
           until every worker has marked a second entry into that path. */
        {
            unsigned attempt;
            int woke = 0;
            unsigned char probe = 0xa5;

            for (attempt = 0; attempt < 1000; attempt++) {
                int count = futex_wake_word(&exit_block_futex, 1);

                if (count == 1) {
                    woke = 1;
                    break;
                }
                if (count < 0)
                    _exit(122);
                usleep(1000);
            }
            /* There is no pipe-state query in this suite; after the call-site
               marker, a delay makes an actual blocked read overwhelmingly
               likely while retaining the unavoidable scheduling window. */
            usleep(10000);
            if (!woke || full_write(exit_block_pipe[1], &probe, 1) != 0)
                _exit(122);
        }
        if (wait_atomic_at_least(&exit_futex_returns, 1, 3000) != 0 ||
            wait_atomic_at_least(&exit_futex_entered, 2, 3000) != 0 ||
            wait_atomic_at_least(&exit_pipe_returns, 1, 3000) != 0 ||
            wait_atomic_at_least(&exit_pipe_entered, 2, 3000) != 0 ||
            wait_atomic_at_least(&exit_sleep_returns, 1, 3000) != 0 ||
            wait_atomic_at_least(&exit_sleep_entered, 2, 3000) != 0)
            _exit(123);

        /* Entry markers are immediately before the calls. No userspace
           protocol can remove the final marker-to-syscall scheduling window. */
        usleep(50000);
        if (atomic_load(&exit_block_errors) != 0)
            _exit(124);
        raw_exit_group(73);
    }

    do {
        result = waitpid(child, &status, 0);
    } while (result < 0 && errno == EINTR);
    close_pipe(exit_block_pipe);
    if (result != child)
        return failf("waitpid for exit_group child: %s", strerror(errno));
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 73)
        return failf("exit_group child status %#x, expected exit 73", status);
    return TEST_OK;
}

/* -------------------------------------------------------------------------- */
/* Isolated watchdog runner                                                   */
/* -------------------------------------------------------------------------- */

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "futex lost-wakeup handshake", test_futex_lost_wakeup_handshake },
    { "remote pipe read wake", test_remote_pipe_read_wake },
    { "directed masked signal pending/unblock", test_directed_masked_signal },
    { "contended pthread mutex counter/progress", test_contended_pthread_mutex },
    { "mixed CPU-bound/sleeper scheduler fairness", test_scheduler_mixed_fairness },
    { "concurrent shared TaskFiles pipe allocation", test_concurrent_pipe_allocation },
    { "concurrent waitpid(-1) exact-once reap", test_concurrent_waitpid_any },
    { "exit_group kills blocked threads", test_exit_group_blocked_threads },
};

#define TEST_TIMEOUT_TICKS 200
#define KILL_REAP_TICKS 20

static void run_isolated(const struct test_case *test)
{
    pid_t pid;
    pid_t result = 0;
    int status = 0;
    unsigned tick;

    printf("[ RUN ] %s\n", test->name);
    pid = fork();
    if (pid < 0) {
        printf("[ FAIL ] %s [fork: %s]\n", test->name, strerror(errno));
        g_failed++;
        return;
    }
    if (pid == 0) {
        int test_result;

        if (setpgid(0, 0) != 0)
            _exit(125);
        test_result = test->run();
        if (test_result < TEST_OK || test_result > TEST_SKIP)
            test_result = TEST_FAILED;
        _exit(test_result);
    }

    for (tick = 0; tick < TEST_TIMEOUT_TICKS && result == 0; tick++) {
        usleep(100000);
        result = waitpid(pid, &status, WNOHANG);
        if (result < 0 && errno == EINTR)
            result = 0;
    }
    if (result == 0) {
        printf("[ FAIL ] %s [timeout after 20 seconds]\n", test->name);
        kill(-pid, SIGKILL);
        kill(pid, SIGKILL);
        for (tick = 0; tick < KILL_REAP_TICKS; tick++) {
            result = waitpid(pid, &status, WNOHANG);
            if (result == pid || (result < 0 && errno == ECHILD))
                break;
            if (result < 0 && errno != EINTR)
                break;
            usleep(100000);
        }
        if (result == 0)
            printf("    watchdog cleanup did not reap test process\n");
        g_failed++;
        return;
    }
    if (result != pid) {
        printf("[ FAIL ] %s [waitpid: %s]\n", test->name, strerror(errno));
        g_failed++;
        return;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == TEST_OK) {
        printf("[ PASS ] %s\n", test->name);
        g_passed++;
    } else if (WIFEXITED(status) &&
               WEXITSTATUS(status) == TEST_SKIP) {
        printf("[ SKIP ] %s [pthread waitpid not permitted]\n",
               test->name);
        g_skipped++;
    } else if (WIFEXITED(status) && WEXITSTATUS(status) == TEST_NEEDS_SMP) {
        printf("[ SKIP ] %s [only one APIC ID observed]\n", test->name);
        g_skipped++;
    } else if (WIFSIGNALED(status)) {
        printf("[ FAIL ] %s [signal %d]\n", test->name, WTERMSIG(status));
        g_failed++;
    } else {
        printf("[ FAIL ] %s [exit status %d]\n", test->name,
               WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        g_failed++;
    }
}

int main(void)
{
    size_t index;

    setvbuf(stdout, NULL, _IONBF, 0);
    puts("=== extended SMP userspace test suite ===");
    for (index = 0; index < ARRAY_SIZE(tests); index++)
        run_isolated(&tests[index]);

    printf("=== %d passed, %d failed, %d skipped ===\n", g_passed, g_failed,
           g_skipped);
    return g_failed ? 1 : 0;
}
