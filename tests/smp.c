/*
 * SMP userspace test suite (i386 Linux ABI)
 *
 * These tests intentionally use only interfaces KFS currently provides.
 * There is no getcpu(2) or affinity support, so CPUID leaf 1's initial APIC
 * ID is used to prove that userspace has executed on more than one CPU.
 *
 * Covers:
 *   - AP scheduling and timer-driven progress on every runnable task
 *   - coherent atomic read/modify/write and release/acquire publication
 *   - futex wakeups reaching waiters running on another CPU
 *   - per-thread TLS and FPU control-state preservation across switches
 *   - remote TLB invalidation after munmap + same-address mmap
 *   - concurrent mmap/munmap operations in one shared address space
 *   - thread teardown and fork/exit while other CPUs use the same mm
 *
 * Cross-CPU assertions are skipped when only one APIC ID is observed.
 *
 * Build:
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *      -o test_smp tests/smp.c -lm
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fenv.h>
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
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SYS_futex
#define SYS_futex 240
#endif

#ifndef SYS_nanosleep
#define SYS_nanosleep 162
#endif

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_PAGE_SIZE 4096u
#define SMP_WORKERS 8
/* KFS's CPU masks support at most 32 CPUs. These tests deliberately create
   more runnable tasks so timer preemption and same-CPU FPU switching occur. */
#define OVERSUBSCRIBED_WORKERS 36

enum test_result {
    TEST_OK = 0,
    TEST_FAILED = 1,
    TEST_NEEDS_SMP = 2,
};

static int g_passed;
static int g_failed;
static int g_skipped;

static void cpu_relax(void)
{
    __asm__ volatile("pause" ::: "memory");
}

static unsigned current_apic_id(void)
{
    unsigned eax, ebx, ecx, edx;

    eax = 1;
    ecx = 0;
    __asm__ volatile("cpuid"
                     : "+a"(eax), "=b"(ebx), "+c"(ecx), "=d"(edx)
                     :
                     : "memory");
    return ebx >> 24;
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

static int join_threads(pthread_t *threads, unsigned count)
{
    unsigned i;

    for (i = 0; i < count; i++) {
        if (pthread_join(threads[i], NULL) != 0)
            return -1;
    }
    return 0;
}

static _Atomic uint32_t cpu_seen[8];

static void reset_cpu_seen(void)
{
    size_t i;

    for (i = 0; i < ARRAY_SIZE(cpu_seen); i++)
        atomic_store_explicit(&cpu_seen[i], 0, memory_order_relaxed);
}

static void mark_current_cpu(void)
{
    unsigned id = current_apic_id();

    atomic_fetch_or_explicit(&cpu_seen[id / 32], 1u << (id % 32),
                             memory_order_relaxed);
}

static unsigned cpu_seen_count(void)
{
    unsigned count = 0;
    size_t i;

    for (i = 0; i < ARRAY_SIZE(cpu_seen); i++)
        count += __builtin_popcount(
            atomic_load_explicit(&cpu_seen[i], memory_order_relaxed));
    return count;
}

/* ------------------------------------------------------------------ */
/* AP execution and local timer preemption                            */
/* ------------------------------------------------------------------ */

static _Atomic unsigned progress_start;
static _Atomic unsigned progress_stop;
static volatile uint64_t progress_counts[OVERSUBSCRIBED_WORKERS];

static void *progress_worker(void *arg)
{
    unsigned index = (unsigned)(uintptr_t)arg;
    uint64_t count = 0;

    while (!atomic_load_explicit(&progress_start, memory_order_acquire))
        cpu_relax();

    while (!atomic_load_explicit(&progress_stop, memory_order_acquire)) {
        count++;
        if ((count & 0x3ff) == 0)
            mark_current_cpu();
    }
    mark_current_cpu();
    progress_counts[index] = count;
    return NULL;
}

static int test_cpu_execution_and_progress(void)
{
    pthread_t threads[OVERSUBSCRIBED_WORKERS];
    unsigned created = 0;
    unsigned i;

    reset_cpu_seen();
    atomic_store(&progress_start, 0);
    atomic_store(&progress_stop, 0);
    memset((void *)progress_counts, 0, sizeof(progress_counts));

    for (i = 0; i < OVERSUBSCRIBED_WORKERS; i++) {
        if (pthread_create(&threads[i], NULL, progress_worker,
                           (void *)(uintptr_t)i) != 0)
            break;
        created++;
    }
    atomic_store_explicit(&progress_start, 1, memory_order_release);
    if (created != OVERSUBSCRIBED_WORKERS) {
        atomic_store(&progress_stop, 1);
        join_threads(threads, created);
        return failf("pthread_create stopped at %u/%u", created,
                     OVERSUBSCRIBED_WORKERS);
    }

    usleep(250000);
    atomic_store_explicit(&progress_stop, 1, memory_order_release);
    if (join_threads(threads, OVERSUBSCRIBED_WORKERS) != 0)
        return failf("pthread_join failed for a progress worker");

    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;
    for (i = 0; i < OVERSUBSCRIBED_WORKERS; i++) {
        if (progress_counts[i] < 100)
            return failf("worker %u made insufficient progress (%llu loops)",
                         i, (unsigned long long)progress_counts[i]);
    }
    return TEST_OK;
}

/* ------------------------------------------------------------------ */
/* Atomic coherence and release/acquire publication                   */
/* ------------------------------------------------------------------ */

#define COUNTER_ITERS 50000u
#define MESSAGE_ITERS 20000u

static _Atomic unsigned counter_start;
static _Atomic uint64_t shared_counter;

static void *counter_worker(void *arg)
{
    unsigned i;

    (void)arg;
    while (!atomic_load_explicit(&counter_start, memory_order_acquire))
        cpu_relax();
    for (i = 0; i < COUNTER_ITERS; i++) {
        atomic_fetch_add_explicit(&shared_counter, 1, memory_order_seq_cst);
        if ((i & 0x3ffu) == 0)
            mark_current_cpu();
    }
    mark_current_cpu();
    return NULL;
}

struct message {
    uint32_t sequence;
    uint32_t inverse;
    uint32_t checksum;
};

static struct message published_message;
static _Atomic unsigned message_turn;
static _Atomic unsigned message_errors;

static uint32_t message_checksum(uint32_t sequence)
{
    return sequence * 0x9e3779b1u ^ (sequence >> 7) ^ 0xa5a55a5au;
}

static void *message_producer(void *arg)
{
    uint32_t i;

    (void)arg;
    for (i = 1; i <= MESSAGE_ITERS; i++) {
        while (atomic_load_explicit(&message_turn, memory_order_acquire) != 0)
            cpu_relax();
        published_message.sequence = i;
        published_message.inverse = ~i;
        published_message.checksum = message_checksum(i);
        atomic_store_explicit(&message_turn, 1, memory_order_release);
        if ((i & 0xff) == 0)
            mark_current_cpu();
    }
    return NULL;
}

static void *message_consumer(void *arg)
{
    uint32_t i;

    (void)arg;
    for (i = 1; i <= MESSAGE_ITERS; i++) {
        while (atomic_load_explicit(&message_turn, memory_order_acquire) != 1)
            cpu_relax();
        if (published_message.sequence != i ||
            published_message.inverse != ~i ||
            published_message.checksum != message_checksum(i))
            atomic_fetch_add_explicit(&message_errors, 1,
                                      memory_order_relaxed);
        atomic_store_explicit(&message_turn, 0, memory_order_release);
        if ((i & 0xff) == 0)
            mark_current_cpu();
    }
    return NULL;
}

static int test_atomic_coherence_and_publication(void)
{
    pthread_t counters[SMP_WORKERS];
    pthread_t producer, consumer;
    uint64_t expected = (uint64_t)SMP_WORKERS * COUNTER_ITERS;
    unsigned i;

    reset_cpu_seen();
    atomic_store(&counter_start, 0);
    atomic_store(&shared_counter, 0);
    for (i = 0; i < SMP_WORKERS; i++) {
        if (pthread_create(&counters[i], NULL, counter_worker, NULL) != 0)
            return failf("could not create atomic counter worker %u", i);
    }
    atomic_store_explicit(&counter_start, 1, memory_order_release);
    if (join_threads(counters, SMP_WORKERS) != 0)
        return failf("pthread_join failed for an atomic counter worker");
    if (atomic_load(&shared_counter) != expected)
        return failf("atomic counter is %llu, expected %llu",
                     (unsigned long long)atomic_load(&shared_counter),
                     (unsigned long long)expected);
    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;

    reset_cpu_seen();
    atomic_store(&message_turn, 0);
    atomic_store(&message_errors, 0);
    if (pthread_create(&producer, NULL, message_producer, NULL) != 0 ||
        pthread_create(&consumer, NULL, message_consumer, NULL) != 0)
        return failf("could not create publication workers");
    if (pthread_join(producer, NULL) != 0 ||
        pthread_join(consumer, NULL) != 0)
        return failf("pthread_join failed for a publication worker");

    if (atomic_load(&message_errors) != 0)
        return failf("release/acquire publication saw %u corrupt messages",
                     atomic_load(&message_errors));
    if (cpu_seen_count() < 2)
        return TEST_NEEDS_SMP;
    return TEST_OK;
}

/* ------------------------------------------------------------------ */
/* Cross-CPU futex wake                                                */
/* ------------------------------------------------------------------ */

static _Atomic int futex_word;
static _Atomic unsigned futex_ready;
static _Atomic unsigned futex_observed;
static _Atomic unsigned futex_errors;
static unsigned futex_cpu_after[SMP_WORKERS];
static _Atomic unsigned futex_woke[SMP_WORKERS];

static int futex_wait_word(_Atomic int *word, int expected)
{
    return syscall(SYS_futex, (int *)word,
                   FUTEX_WAIT | FUTEX_PRIVATE_FLAG, expected,
                   NULL, NULL, 0);
}

static int futex_wake_word(_Atomic int *word, int count)
{
    return syscall(SYS_futex, (int *)word,
                   FUTEX_WAKE | FUTEX_PRIVATE_FLAG, count,
                   NULL, NULL, 0);
}

static void *futex_waiter(void *arg)
{
    unsigned index = (unsigned)(uintptr_t)arg;

    atomic_fetch_add_explicit(&futex_ready, 1, memory_order_release);
    while (atomic_load_explicit(&futex_word, memory_order_acquire) == 0) {
        int result = futex_wait_word(&futex_word, 0);

        if (result == 0)
            atomic_store_explicit(&futex_woke[index], 1,
                                  memory_order_release);
        if (result < 0 && errno != EAGAIN && errno != EINTR) {
            atomic_fetch_add(&futex_errors, 1);
            return NULL;
        }
    }
    futex_cpu_after[index] = current_apic_id();
    atomic_fetch_add_explicit(&futex_observed, 1, memory_order_relaxed);
    return NULL;
}

static int test_cross_cpu_futex_wake(void)
{
    pthread_t threads[SMP_WORKERS];
    unsigned main_cpu;
    unsigned remote_woken = 0;
    unsigned i;
    unsigned attempts;
    unsigned probe_woken = 0;

    atomic_store(&futex_word, 0);
    atomic_store(&futex_ready, 0);
    atomic_store(&futex_observed, 0);
    atomic_store(&futex_errors, 0);
    memset(futex_cpu_after, 0, sizeof(futex_cpu_after));
    for (i = 0; i < SMP_WORKERS; i++)
        atomic_store(&futex_woke[i], 0);
    for (i = 0; i < SMP_WORKERS; i++) {
        if (pthread_create(&threads[i], NULL, futex_waiter,
                           (void *)(uintptr_t)i) != 0)
            return failf("could not create futex waiter %u", i);
    }
    while (atomic_load_explicit(&futex_ready, memory_order_acquire) !=
           SMP_WORKERS)
        cpu_relax();

    main_cpu = current_apic_id();

    /* Keep the word unchanged and probe with wake-all until every waiter has
       demonstrably returned from FUTEX_WAIT at least once. This proves queue
       insertion without assuming that a fixed delay was long enough. */
    for (attempts = 0; attempts < 1000; attempts++) {
        unsigned confirmed = 0;
        int probe = futex_wake_word(&futex_word, INT_MAX);

        if (probe < 0)
            return failf("FUTEX_WAKE probe failed: %s", strerror(errno));
        probe_woken += (unsigned)probe;
        for (i = 0; i < SMP_WORKERS; i++)
            confirmed += atomic_load_explicit(&futex_woke[i],
                                              memory_order_acquire) != 0;
        if (confirmed == SMP_WORKERS)
            break;
        usleep(1000);
    }
    if (attempts == 1000)
        return failf("not every futex waiter entered the wait queue");

    atomic_store_explicit(&futex_word, 1, memory_order_release);
    (void)futex_wake_word(&futex_word, INT_MAX);
    if (join_threads(threads, SMP_WORKERS) != 0)
        return failf("pthread_join failed for a futex waiter");

    for (i = 0; i < SMP_WORKERS; i++) {
        if (atomic_load(&futex_woke[i]) && futex_cpu_after[i] != main_cpu)
            remote_woken++;
    }
    if (probe_woken < SMP_WORKERS)
        return failf("FUTEX_WAKE reported only %u successful probe wakes",
                     probe_woken);
    if (atomic_load(&futex_errors) != 0 ||
        atomic_load(&futex_observed) != SMP_WORKERS)
        return failf("only %u/%u waiters observed the wake (%u errors)",
                     atomic_load(&futex_observed), SMP_WORKERS,
                     atomic_load(&futex_errors));
    if (remote_woken == 0)
        return TEST_NEEDS_SMP;
    return TEST_OK;
}

/* ------------------------------------------------------------------ */
/* TLS and FPU state across context switches                          */
/* ------------------------------------------------------------------ */

static _Thread_local uintptr_t tls_cookie;
static _Atomic unsigned context_ready;
static _Atomic unsigned context_start;
static _Atomic unsigned context_errors;

struct context_arg {
    unsigned index;
    int rounding;
};

static uint16_t x87_control_word(void)
{
    uint16_t control;

    __asm__ volatile("fnstcw %0" : "=m"(control));
    return control;
}

static uint32_t sse_control_word(void)
{
    uint32_t control;

    __asm__ volatile("stmxcsr %0" : "=m"(control));
    return control;
}

static void *context_worker(void *opaque)
{
    struct context_arg *arg = opaque;
    uintptr_t expected = 0x51f00000u + arg->index * 0x101u;
    unsigned i;

    tls_cookie = expected;
    if (fesetround(arg->rounding) != 0)
        atomic_fetch_add(&context_errors, 1);
    atomic_fetch_add_explicit(&context_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&context_start, memory_order_acquire))
        cpu_relax();

    for (i = 0; i < 100; i++) {
        _Alignas(16) uint32_t xmm_expected[4] = {
            0x10000000u | arg->index,
            0x20000000u | i,
            0x30000000u | (arg->index << 16) | i,
            0x40000000u | (arg->index * 0x101u + i),
        };
        _Alignas(16) uint32_t xmm_observed[4];
        int32_t x87_expected = (int32_t)(0x1000 + arg->index * 101 + i);
        int32_t x87_observed;
        struct {
            int32_t tv_sec;
            int32_t tv_nsec;
        } delay = { .tv_sec = 0, .tv_nsec = 1000000 };
        long syscall_result;
        uint16_t x87_control;
        uint32_t sse_control;

        x87_control = x87_control_word();
        sse_control = sse_control_word();
        if (tls_cookie != expected || fegetround() != arg->rounding ||
            (x87_control & 0x0c00u) != (uint16_t)arg->rounding ||
            (sse_control & 0x6000u) != ((uint32_t)arg->rounding << 3))
            atomic_fetch_add_explicit(&context_errors, 1,
                                      memory_order_relaxed);

        __asm__ volatile("fildl %0" : : "m"(x87_expected));
        __asm__ volatile("movdqu %0, %%xmm7"
                         : : "m"(xmm_expected) : "xmm7");
        __asm__ volatile("int $0x80"
                         : "=a"(syscall_result)
                         : "0"((long)SYS_nanosleep), "b"(&delay), "c"(0)
                         : "memory", "cc");
        __asm__ volatile("movdqu %%xmm7, %0"
                         : "=m"(xmm_observed));
        __asm__ volatile("fistpl %0" : "=m"(x87_observed));

        x87_control = x87_control_word();
        sse_control = sse_control_word();
        if (syscall_result != 0 || tls_cookie != expected ||
            x87_observed != x87_expected ||
            memcmp(xmm_observed, xmm_expected, sizeof(xmm_expected)) != 0 ||
            (x87_control & 0x0c00u) != (uint16_t)arg->rounding ||
            (sse_control & 0x6000u) != ((uint32_t)arg->rounding << 3))
            atomic_fetch_add_explicit(&context_errors, 1,
                                      memory_order_relaxed);
    }
    return NULL;
}

static int test_tls_and_fpu_context(void)
{
    static const int roundings[] = {
        FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO,
    };
    struct context_arg args[OVERSUBSCRIBED_WORKERS];
    pthread_t threads[OVERSUBSCRIBED_WORKERS];
    unsigned i;

    atomic_store(&context_ready, 0);
    atomic_store(&context_start, 0);
    atomic_store(&context_errors, 0);
    for (i = 0; i < OVERSUBSCRIBED_WORKERS; i++) {
        args[i].index = i;
        args[i].rounding = roundings[i % ARRAY_SIZE(roundings)];
        if (pthread_create(&threads[i], NULL, context_worker, &args[i]) != 0)
            return failf("could not create context worker %u", i);
    }
    while (atomic_load_explicit(&context_ready, memory_order_acquire) !=
           OVERSUBSCRIBED_WORKERS)
        cpu_relax();
    atomic_store_explicit(&context_start, 1, memory_order_release);
    if (join_threads(threads, OVERSUBSCRIBED_WORKERS) != 0)
        return failf("pthread_join failed for a context worker");

    if (atomic_load(&context_errors) != 0)
        return failf("TLS/FPU state changed unexpectedly %u times",
                     atomic_load(&context_errors));
    return 0;
}

/* ------------------------------------------------------------------ */
/* TLB shootdown                                                       */
/* ------------------------------------------------------------------ */

#define TLB_OLD_VALUE 0x11223344u
#define TLB_GUARD_VALUE 0x55667788u
#define TLB_NEW_VALUE 0xaabbccddu
#define TLB_WORKERS 6

static volatile uint32_t *tlb_target;
static _Atomic unsigned tlb_phase;
static _Atomic unsigned tlb_ready;
static _Atomic unsigned tlb_initial_errors;
static uint32_t tlb_seen[TLB_WORKERS];
static unsigned tlb_cpu_before[TLB_WORKERS];
static unsigned tlb_cpu_after[TLB_WORKERS];

static void *tlb_worker(void *arg)
{
    unsigned index = (unsigned)(uintptr_t)arg;
    uint32_t value;

    while (atomic_load_explicit(&tlb_phase, memory_order_acquire) == 0)
        cpu_relax();

    /* Populate this CPU's TLB before the mapping is replaced. */
    tlb_cpu_before[index] = current_apic_id();
    value = *tlb_target;
    if (value != TLB_OLD_VALUE)
        atomic_fetch_add_explicit(&tlb_initial_errors, 1,
                                  memory_order_relaxed);
    mark_current_cpu();
    atomic_fetch_add_explicit(&tlb_ready, 1, memory_order_release);

    while (atomic_load_explicit(&tlb_phase, memory_order_acquire) == 1)
        cpu_relax();
    tlb_seen[index] = *tlb_target;
    tlb_cpu_after[index] = current_apic_id();
    return NULL;
}

static int test_tlb_shootdown(void)
{
    pthread_t threads[TLB_WORKERS];
    uint8_t *region;
    volatile uint32_t *guard;
    volatile uint32_t *fresh;
    uint32_t stable_cpus[8] = {0};
    unsigned populated_cpu_count;
    unsigned stable_cpu_count = 0;
    unsigned i;

    reset_cpu_seen();
    atomic_store(&tlb_phase, 0);
    atomic_store(&tlb_ready, 0);
    atomic_store(&tlb_initial_errors, 0);
    memset(tlb_seen, 0, sizeof(tlb_seen));
    memset(tlb_cpu_before, 0, sizeof(tlb_cpu_before));
    memset(tlb_cpu_after, 0, sizeof(tlb_cpu_after));

    /*
     * Create the workers before mapping the test region otherwise the test
     * might fail with exit code 11 due to trying to unmap regions where thread
     * stacks live.
     */
    for (i = 0; i < TLB_WORKERS; i++) {
        if (pthread_create(&threads[i], NULL, tlb_worker,
                           (void *)(uintptr_t)i) != 0)
            return failf("could not create TLB worker %u", i);
    }

    region = mmap(NULL, 3 * TEST_PAGE_SIZE, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (region == MAP_FAILED)
        return failf("initial mmap failed: %s", strerror(errno));

    tlb_target = (volatile uint32_t *)region;
    *tlb_target = TLB_OLD_VALUE;
    *(volatile uint32_t *)(region + TEST_PAGE_SIZE) = 0xdeadbeefu;

    /* Free a higher physical page first. After target is freed, mapping the
       high hole normally consumes target's old page and makes a stale TLB
       translation read TLB_GUARD_VALUE instead of accidentally passing. */
    if (munmap(region + 2 * TEST_PAGE_SIZE, TEST_PAGE_SIZE) != 0)
        return failf("could not make remap guard hole: %s", strerror(errno));

    atomic_store_explicit(&tlb_phase, 1, memory_order_release);
    while (atomic_load_explicit(&tlb_ready, memory_order_acquire) !=
           TLB_WORKERS)
        cpu_relax();

    populated_cpu_count = cpu_seen_count();
    if (atomic_load(&tlb_initial_errors) != 0)
        return failf("%u workers failed to establish the old mapping",
                     atomic_load(&tlb_initial_errors));
    if (munmap(region, TEST_PAGE_SIZE) != 0)
        return failf("target munmap failed: %s", strerror(errno));

    guard = mmap(region + 2 * TEST_PAGE_SIZE, TEST_PAGE_SIZE,
                 PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (guard == MAP_FAILED)
        return failf("guard mmap failed: %s", strerror(errno));
    if ((void *)guard != region + 2 * TEST_PAGE_SIZE)
        return failf("kernel did not honor the free guard-page hint");
    *guard = TLB_GUARD_VALUE;

    fresh = mmap(region, TEST_PAGE_SIZE, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (fresh == MAP_FAILED)
        return failf("replacement mmap failed: %s", strerror(errno));
    if ((void *)fresh != region)
        return failf("kernel did not honor the free replacement-page hint");
    *fresh = TLB_NEW_VALUE;

    atomic_store_explicit(&tlb_phase, 2, memory_order_release);
    if (join_threads(threads, TLB_WORKERS) != 0)
        return failf("pthread_join failed for a TLB worker");

    for (i = 0; i < TLB_WORKERS; i++) {
        unsigned id;

        if (tlb_cpu_after[i] != tlb_cpu_before[i])
            continue;
        id = tlb_cpu_after[i];
        stable_cpus[id / 32] |= 1u << (id % 32);
        if (tlb_seen[i] != TLB_NEW_VALUE)
            return failf("worker %u read %#x after remap, expected %#x", i,
                         tlb_seen[i], TLB_NEW_VALUE);
    }
    for (i = 0; i < ARRAY_SIZE(stable_cpus); i++)
        stable_cpu_count += __builtin_popcount(stable_cpus[i]);
    if (munmap(region, 3 * TEST_PAGE_SIZE) != 0)
        return failf("final munmap failed: %s", strerror(errno));
    if (stable_cpu_count < 2) {
        if (populated_cpu_count < 2)
            return TEST_NEEDS_SMP;
        return failf("fewer than two workers stayed on one CPU for remap");
    }
    return TEST_OK;
}

/* ------------------------------------------------------------------ */
/* Shared-mm VMA mutation                                              */
/* ------------------------------------------------------------------ */

#define MMAP_ITERS 30

static _Atomic unsigned mmap_start;
static _Atomic unsigned mmap_errors;
static _Atomic unsigned mmap_ready;
static _Atomic unsigned mmap_filled;
static _Atomic unsigned mmap_checked;
static _Atomic unsigned mmap_unmapped;
static _Atomic uintptr_t mmap_active[SMP_WORKERS];

static void wait_for_count(_Atomic unsigned *counter, unsigned target)
{
    while (atomic_load_explicit(counter, memory_order_acquire) < target)
        cpu_relax();
}

static void *mmap_worker(void *arg)
{
    unsigned index = (unsigned)(uintptr_t)arg;
    unsigned iteration;

    while (!atomic_load_explicit(&mmap_start, memory_order_acquire))
        cpu_relax();
    for (iteration = 0; iteration < MMAP_ITERS; iteration++) {
        uint32_t pattern = ((iteration + 1) << 16) | (index + 1);
        _Atomic uint32_t *page = mmap(NULL, TEST_PAGE_SIZE,
                                      PROT_READ | PROT_WRITE,
                                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        unsigned target = (iteration + 1) * SMP_WORKERS;
        size_t word;
        unsigned other;

        if ((void *)page == MAP_FAILED) {
            atomic_fetch_add(&mmap_errors, 1);
            page = NULL;
        }
        atomic_store_explicit(&mmap_active[index], (uintptr_t)page,
                              memory_order_release);
        atomic_fetch_add_explicit(&mmap_ready, 1, memory_order_release);
        wait_for_count(&mmap_ready, target);

        if (page != NULL) {
            for (other = 0; other < SMP_WORKERS; other++) {
                if (other != index &&
                    atomic_load_explicit(&mmap_active[other],
                                         memory_order_acquire) ==
                        (uintptr_t)page)
                    atomic_fetch_add(&mmap_errors, 1);
            }
            for (word = 0; word < TEST_PAGE_SIZE / sizeof(uint32_t); word++)
                atomic_store_explicit(&page[word], pattern,
                                      memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&mmap_filled, 1, memory_order_release);
        wait_for_count(&mmap_filled, target);

        if (page != NULL) {
            for (word = 0; word < TEST_PAGE_SIZE / sizeof(uint32_t); word++) {
                if (atomic_load_explicit(&page[word], memory_order_relaxed) !=
                    pattern) {
                    atomic_fetch_add(&mmap_errors, 1);
                    break;
                }
            }
        }
        atomic_fetch_add_explicit(&mmap_checked, 1, memory_order_release);
        wait_for_count(&mmap_checked, target);

        atomic_store_explicit(&mmap_active[index], 0, memory_order_release);
        if (page != NULL && munmap((void *)page, TEST_PAGE_SIZE) != 0)
            atomic_fetch_add(&mmap_errors, 1);
        atomic_fetch_add_explicit(&mmap_unmapped, 1, memory_order_release);
        wait_for_count(&mmap_unmapped, target);
    }
    return NULL;
}

static int test_concurrent_mmap_churn(void)
{
    pthread_t threads[SMP_WORKERS];
    unsigned i;

    atomic_store(&mmap_start, 0);
    atomic_store(&mmap_errors, 0);
    atomic_store(&mmap_ready, 0);
    atomic_store(&mmap_filled, 0);
    atomic_store(&mmap_checked, 0);
    atomic_store(&mmap_unmapped, 0);
    for (i = 0; i < SMP_WORKERS; i++)
        atomic_store(&mmap_active[i], 0);
    for (i = 0; i < SMP_WORKERS; i++) {
        if (pthread_create(&threads[i], NULL, mmap_worker,
                           (void *)(uintptr_t)i) != 0)
            return failf("could not create mmap worker %u", i);
    }
    atomic_store_explicit(&mmap_start, 1, memory_order_release);
    if (join_threads(threads, SMP_WORKERS) != 0)
        return failf("pthread_join failed for an mmap worker");

    if (atomic_load(&mmap_errors) != 0)
        return failf("concurrent mmap/munmap reported %u corruptions/errors",
                     atomic_load(&mmap_errors));
    return 0;
}

/* ------------------------------------------------------------------ */
/* Task creation, teardown, and fork while the mm is active elsewhere */
/* ------------------------------------------------------------------ */

#define CHURN_ROUNDS 6
#define FORK_CHILDREN 6

static _Atomic unsigned churn_completions;
static _Atomic unsigned lifecycle_start;
static _Atomic unsigned lifecycle_stop;
static _Atomic unsigned lifecycle_ready;
static _Atomic uint32_t lifecycle_ticks[SMP_WORKERS];
static _Atomic uint32_t lifecycle_marker;
static uint32_t lifecycle_expected;

static void *short_lived_worker(void *arg)
{
    uintptr_t value = (uintptr_t)arg + 1;
    uintptr_t expected = 0x70000000u + value;

    tls_cookie = expected;
    usleep(1000);
    if (tls_cookie == expected)
        atomic_fetch_add_explicit(&churn_completions, 1,
                                  memory_order_relaxed);
    return (void *)value;
}

static void *lifecycle_worker(void *arg)
{
    unsigned index = (unsigned)(uintptr_t)arg;
    atomic_fetch_add_explicit(&lifecycle_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&lifecycle_start, memory_order_acquire))
        cpu_relax();
    while (!atomic_load_explicit(&lifecycle_stop, memory_order_acquire)) {
        if (atomic_load_explicit(&lifecycle_marker, memory_order_relaxed) !=
            lifecycle_expected)
            abort();
        atomic_fetch_add_explicit(&lifecycle_ticks[index], 1,
                                  memory_order_relaxed);
    }
    return NULL;
}

static int test_task_and_mm_lifecycle(void)
{
    pthread_t threads[SMP_WORKERS];
    pid_t children[FORK_CHILDREN];
    uint32_t ticks_before[SMP_WORKERS];
    unsigned round, i;
    int failed = 0;

    atomic_store(&churn_completions, 0);
    for (round = 0; round < CHURN_ROUNDS; round++) {
        for (i = 0; i < SMP_WORKERS; i++) {
            if (pthread_create(&threads[i], NULL, short_lived_worker,
                               (void *)(uintptr_t)i) != 0)
                return failf("thread churn create failed in round %u", round);
        }
        for (i = 0; i < SMP_WORKERS; i++) {
            void *result = NULL;

            if (pthread_join(threads[i], &result) != 0 ||
                (uintptr_t)result != i + 1)
                failed = 1;
        }
    }
    if (failed || atomic_load(&churn_completions) !=
                      CHURN_ROUNDS * SMP_WORKERS)
        return failf("thread creation/teardown lost completions");

    atomic_store(&lifecycle_start, 0);
    atomic_store(&lifecycle_stop, 0);
    atomic_store(&lifecycle_ready, 0);
    lifecycle_expected = 0xc001d00du ^ (uint32_t)getpid() ^ current_apic_id();
    atomic_store(&lifecycle_marker, lifecycle_expected);
    for (i = 0; i < SMP_WORKERS; i++)
        atomic_store(&lifecycle_ticks[i], 0);
    for (i = 0; i < SMP_WORKERS; i++) {
        if (pthread_create(&threads[i], NULL, lifecycle_worker,
                           (void *)(uintptr_t)i) != 0)
            return failf("could not create lifecycle worker %u", i);
    }
    while (atomic_load_explicit(&lifecycle_ready, memory_order_acquire) !=
           SMP_WORKERS)
        cpu_relax();
    atomic_store_explicit(&lifecycle_start, 1, memory_order_release);
    for (i = 0; i < SMP_WORKERS; i++) {
        while (atomic_load_explicit(&lifecycle_ticks[i],
                                    memory_order_relaxed) == 0)
            cpu_relax();
        ticks_before[i] = atomic_load_explicit(&lifecycle_ticks[i],
                                               memory_order_relaxed);
    }

    for (i = 0; i < FORK_CHILDREN; i++) {
        children[i] = fork();
        if (children[i] == 0) {
            uint32_t private_value = lifecycle_expected ^ (0x10000u + i);

            if (atomic_load(&lifecycle_marker) != lifecycle_expected)
                _exit(1);
            atomic_store(&lifecycle_marker, private_value);
            usleep(50000);
            _exit(atomic_load(&lifecycle_marker) == private_value ? 0 : 2);
        }
        if (children[i] < 0) {
            atomic_store(&lifecycle_stop, 1);
            return failf("fork %u failed: %s", i, strerror(errno));
        }
    }
    for (i = 0; i < FORK_CHILDREN; i++) {
        int status = 0;

        if (waitpid(children[i], &status, 0) != children[i] ||
            !WIFEXITED(status) || WEXITSTATUS(status) != 0)
            failed = 1;
    }
    for (i = 0; i < SMP_WORKERS; i++) {
        if (atomic_load_explicit(&lifecycle_ticks[i], memory_order_relaxed) <=
            ticks_before[i])
            failed = 1;
    }
    if (atomic_load(&lifecycle_marker) != lifecycle_expected)
        failed = 1;

    atomic_store_explicit(&lifecycle_stop, 1, memory_order_release);
    if (join_threads(threads, SMP_WORKERS) != 0)
        failed = 1;

    for (i = 0; i < SMP_WORKERS; i++) {
        if (atomic_load(&lifecycle_ticks[i]) == 0)
            failed = 1;
    }
    if (failed)
        return failf("fork/exit or background task progress failed");
    return 0;
}

/* ------------------------------------------------------------------ */
/* Isolated watchdog runner                                            */
/* ------------------------------------------------------------------ */

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "AP execution and timer progress", test_cpu_execution_and_progress },
    { "atomic coherence and publication", test_atomic_coherence_and_publication },
    { "cross-CPU futex wake", test_cross_cpu_futex_wake },
    { "TLS and FPU context isolation", test_tls_and_fpu_context },
    { "TLB shootdown on remap", test_tlb_shootdown },
    { "concurrent mmap/munmap", test_concurrent_mmap_churn },
    { "task and mm lifecycle", test_task_and_mm_lifecycle },
};

#define TEST_TIMEOUT_TICKS 200 /* 20 seconds per test */

static void run_isolated(const struct test_case *test)
{
    pid_t pid;
    pid_t result = 0;
    int status = 0;
    unsigned tick;

    printf("[ RUN   ] %s\n", test->name);
    pid = fork();
    if (pid < 0) {
        printf("[ FAIL  ] %s [fork: %s]\n", test->name, strerror(errno));
        g_failed++;
        return;
    }
    if (pid == 0) {
        int test_result;

        if (setpgid(0, 0) != 0)
            _exit(125);
        test_result = test->run();
        if (test_result < TEST_OK || test_result > TEST_NEEDS_SMP)
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
        printf("[ FAIL  ] %s [timeout after 20 seconds]\n", test->name);
        kill(-pid, SIGKILL);
        kill(pid, SIGKILL);
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
            ;
        g_failed++;
        return;
    }
    if (result != pid) {
        printf("[ FAIL  ] %s [waitpid: %s]\n", test->name, strerror(errno));
        g_failed++;
        return;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        printf("[ PASS  ] %s\n", test->name);
        g_passed++;
    } else if (WIFEXITED(status) &&
               WEXITSTATUS(status) == TEST_NEEDS_SMP) {
        printf("[ SKIP  ] %s [only one APIC ID observed]\n", test->name);
        g_skipped++;
    } else if (WIFSIGNALED(status)) {
        printf("[ FAIL  ] %s [signal %d]\n", test->name, WTERMSIG(status));
        g_failed++;
    } else {
        printf("[ FAIL  ] %s [exit status %d]\n", test->name,
               WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        g_failed++;
    }
}

int main(void)
{
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    puts("=== SMP userspace test suite ===");
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_isolated(&tests[i]);

    printf("\n=== %d passed, %d failed, %d skipped ===\n", g_passed,
           g_failed, g_skipped);
    return g_failed ? 1 : 0;
}
