/*
 * pthread/clone test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_threads tests/threads.c
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
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SYS_exit
#define SYS_exit 1
#endif
#ifndef SYS_gettid
#define SYS_gettid 224
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define THREAD_COUNT 6

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

static pid_t current_tid(void)
{
    return (pid_t)syscall(SYS_gettid);
}

struct id_result {
    pid_t tid;
    pid_t pid;
};

static struct id_result id_results[THREAD_COUNT];
static _Atomic unsigned id_ready;
static _Atomic int id_release;

static void *id_worker(void *opaque)
{
    unsigned index = (unsigned)(uintptr_t)opaque;

    id_results[index].tid = current_tid();
    id_results[index].pid = getpid();
    atomic_fetch_add_explicit(&id_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&id_release, memory_order_acquire))
        ;
    return NULL;
}

static int test_thread_ids(void)
{
    pthread_t threads[THREAD_COUNT];
    pid_t pid = getpid();
    pid_t main_tid = current_tid();
    unsigned i;
    unsigned j;
    unsigned created = 0;

    memset(id_results, 0, sizeof(id_results));
    atomic_store(&id_ready, 0);
    atomic_store(&id_release, 0);
    for (i = 0; i < THREAD_COUNT; i++) {
        int rc = pthread_create(&threads[i], NULL, id_worker,
                                (void *)(uintptr_t)i);
        if (rc != 0) {
            unsigned k;

            atomic_store_explicit(&id_release, 1, memory_order_release);
            for (k = 0; k < created; k++)
                (void)pthread_join(threads[k], NULL);
            return failf("pthread_create %u failed: %s", i, strerror(rc));
        }
        created++;
    }
    while (atomic_load_explicit(&id_ready, memory_order_acquire) !=
           THREAD_COUNT)
        ;
    atomic_store_explicit(&id_release, 1, memory_order_release);
    for (i = 0; i < THREAD_COUNT; i++) {
        int rc = pthread_join(threads[i], NULL);
        if (rc != 0)
            return failf("pthread_join %u failed: %s", i, strerror(rc));
    }
    if (main_tid != pid)
        return failf("main gettid differs from getpid");
    for (i = 0; i < THREAD_COUNT; i++) {
        if (id_results[i].pid != pid || id_results[i].tid <= 0 ||
            id_results[i].tid == main_tid)
            return failf("thread %u had invalid PID/TID", i);
        for (j = 0; j < i; j++) {
            if (id_results[i].tid == id_results[j].tid)
                return failf("threads %u and %u shared a TID", i, j);
        }
    }
    return 0;
}

static _Thread_local uintptr_t tls_value;
static _Atomic unsigned tls_errors;

static void *tls_worker(void *opaque)
{
    uintptr_t expected = (uintptr_t)opaque + 0x10203040u;
    unsigned i;

    tls_value = expected;
    for (i = 0; i < 100; i++) {
        usleep(100);
        if (tls_value != expected)
            atomic_fetch_add(&tls_errors, 1);
    }
    return (void *)expected;
}

static int test_tls_and_return_join(void)
{
    pthread_t threads[THREAD_COUNT];
    unsigned created = 0;
    unsigned i;

    tls_value = 0x55aa55aau;
    atomic_store(&tls_errors, 0);
    for (i = 0; i < THREAD_COUNT; i++) {
        int rc = pthread_create(&threads[i], NULL, tls_worker,
                                (void *)(uintptr_t)(i + 1));
        if (rc != 0) {
            unsigned j;

            for (j = 0; j < created; j++)
                (void)pthread_join(threads[j], NULL);
            return failf("pthread_create %u failed: %s", i, strerror(rc));
        }
        created++;
    }
    for (i = 0; i < THREAD_COUNT; i++) {
        void *result = NULL;
        uintptr_t expected = i + 1 + 0x10203040u;
        int rc = pthread_join(threads[i], &result);

        if (rc != 0 || (uintptr_t)result != expected)
            return failf("thread %u join/return value was wrong", i);
    }
    if (tls_value != 0x55aa55aau || atomic_load(&tls_errors) != 0)
        return failf("thread-local storage was not isolated");
    return 0;
}

static pthread_mutex_t count_mutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned protected_count;
static _Atomic unsigned mutex_errors;

static void *mutex_worker(void *unused)
{
    unsigned i;

    (void)unused;
    for (i = 0; i < 1000; i++) {
        if (pthread_mutex_lock(&count_mutex) != 0) {
            atomic_fetch_add(&mutex_errors, 1);
            return NULL;
        }
        protected_count++;
        if (pthread_mutex_unlock(&count_mutex) != 0) {
            atomic_fetch_add(&mutex_errors, 1);
            return NULL;
        }
    }
    return NULL;
}

static int test_process_private_mutex(void)
{
    pthread_t threads[THREAD_COUNT];
    unsigned created = 0;
    unsigned i;

    protected_count = 0;
    atomic_store(&mutex_errors, 0);
    for (i = 0; i < THREAD_COUNT; i++) {
        int rc = pthread_create(&threads[i], NULL, mutex_worker, NULL);
        if (rc != 0) {
            unsigned j;

            for (j = 0; j < created; j++)
                (void)pthread_join(threads[j], NULL);
            return failf("pthread_create failed: %s", strerror(rc));
        }
        created++;
    }
    for (i = 0; i < THREAD_COUNT; i++) {
        int rc = pthread_join(threads[i], NULL);

        if (rc != 0)
            return failf("pthread_join failed: %s", strerror(rc));
    }
    if (atomic_load(&mutex_errors) != 0)
        return failf("pthread mutex operation failed");
    if (protected_count != THREAD_COUNT * 1000u)
        return failf("mutex-protected count was %u", protected_count);
    return 0;
}

static pthread_mutex_t cond_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static int cond_ready;
static unsigned cond_woke;
static _Atomic unsigned cond_errors;

static void *cond_worker(void *unused)
{
    (void)unused;
    if (pthread_mutex_lock(&cond_mutex) != 0) {
        atomic_fetch_add(&cond_errors, 1);
        return NULL;
    }
    while (!cond_ready) {
        if (pthread_cond_wait(&condition, &cond_mutex) != 0) {
            atomic_fetch_add(&cond_errors, 1);
            (void)pthread_mutex_unlock(&cond_mutex);
            return NULL;
        }
    }
    cond_woke++;
    if (pthread_mutex_unlock(&cond_mutex) != 0)
        atomic_fetch_add(&cond_errors, 1);
    return NULL;
}

static int test_process_private_condition(void)
{
    pthread_t threads[THREAD_COUNT];
    unsigned created = 0;
    unsigned i;
    int operation_error = 0;

    cond_ready = 0;
    cond_woke = 0;
    atomic_store(&cond_errors, 0);
    for (i = 0; i < THREAD_COUNT; i++) {
        int rc = pthread_create(&threads[i], NULL, cond_worker, NULL);
        if (rc != 0) {
            operation_error = rc;
            break;
        }
        created++;
    }
    {
        int rc = pthread_mutex_lock(&cond_mutex);

        if (rc != 0)
            return failf("pthread_mutex_lock failed: %s", strerror(rc));
        cond_ready = 1;
        rc = pthread_cond_broadcast(&condition);
        if (rc != 0)
            operation_error = rc;
        rc = pthread_mutex_unlock(&cond_mutex);
        if (rc != 0)
            return failf("pthread_mutex_unlock failed: %s", strerror(rc));
    }
    for (i = 0; i < created; i++) {
        int rc = pthread_join(threads[i], NULL);

        if (rc != 0)
            return failf("pthread_join failed: %s", strerror(rc));
    }
    if (operation_error != 0)
        return failf("pthread condition/create operation failed: %s",
                     strerror(operation_error));
    if (atomic_load(&cond_errors) != 0)
        return failf("pthread condition worker operation failed");
    if (cond_woke != THREAD_COUNT)
        return failf("condition woke %u/%u threads", cond_woke, THREAD_COUNT);
    return 0;
}

static pthread_barrier_t barrier;
static _Atomic unsigned barrier_before;
static _Atomic unsigned barrier_after;
static _Atomic unsigned barrier_errors;
static _Atomic int barrier_start;

static void *barrier_worker(void *unused)
{
    int rc;

    (void)unused;
    while (atomic_load_explicit(&barrier_start, memory_order_acquire) == 0)
        ;
    if (atomic_load_explicit(&barrier_start, memory_order_acquire) < 0)
        return NULL;
    atomic_fetch_add(&barrier_before, 1);
    rc = pthread_barrier_wait(&barrier);
    if (rc != 0 && rc != PTHREAD_BARRIER_SERIAL_THREAD)
        atomic_fetch_add(&barrier_errors, 1);
    if (atomic_load(&barrier_before) != THREAD_COUNT)
        atomic_fetch_add(&barrier_errors, 1);
    atomic_fetch_add(&barrier_after, 1);
    return NULL;
}

static int test_process_private_barrier(void)
{
    pthread_t threads[THREAD_COUNT];
    unsigned created = 0;
    unsigned i;
    int rc;

    atomic_store(&barrier_before, 0);
    atomic_store(&barrier_after, 0);
    atomic_store(&barrier_errors, 0);
    atomic_store(&barrier_start, 0);
    rc = pthread_barrier_init(&barrier, NULL, THREAD_COUNT);
    if (rc != 0)
        return failf("pthread_barrier_init failed: %s", strerror(rc));
    for (i = 0; i < THREAD_COUNT; i++) {
        rc = pthread_create(&threads[i], NULL, barrier_worker, NULL);
        if (rc != 0) {
            unsigned j;

            atomic_store_explicit(&barrier_start, -1, memory_order_release);
            for (j = 0; j < created; j++)
                (void)pthread_join(threads[j], NULL);
            (void)pthread_barrier_destroy(&barrier);
            return failf("pthread_create failed: %s", strerror(rc));
        }
        created++;
    }
    atomic_store_explicit(&barrier_start, 1, memory_order_release);
    for (i = 0; i < THREAD_COUNT; i++) {
        rc = pthread_join(threads[i], NULL);
        if (rc != 0)
            return failf("pthread_join failed: %s", strerror(rc));
    }
    rc = pthread_barrier_destroy(&barrier);
    if (rc != 0)
        return failf("pthread_barrier_destroy failed: %s", strerror(rc));
    if (atomic_load(&barrier_after) != THREAD_COUNT ||
        atomic_load(&barrier_errors) != 0)
        return failf("pthread barrier did not release all participants");
    return 0;
}

struct raw_exit_pipes {
    int ready_write;
    int command_read;
};

static _Atomic int raw_worker_started;
static struct raw_exit_pipes raw_pipes;

static void *raw_exit_survivor(void *opaque)
{
    struct raw_exit_pipes *pipes = opaque;
    char byte = 'R';

    atomic_store_explicit(&raw_worker_started, 1, memory_order_release);
    if (write(pipes->ready_write, &byte, 1) != 1)
        syscall(SYS_exit, 90);
    if (read(pipes->command_read, &byte, 1) != 1)
        syscall(SYS_exit, 91);
    syscall(SYS_exit, 37);
    return NULL;
}

static int test_raw_exit_only_caller(void)
{
    int ready[2];
    int command[2];
    pid_t pid;
    char byte;
    int status = 0;

    if (pipe(ready) != 0 || pipe(command) != 0)
        return failf("pipe failed: %s", strerror(errno));
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        pthread_t thread;

        close(ready[0]);
        close(command[1]);
        raw_pipes.ready_write = ready[1];
        raw_pipes.command_read = command[0];
        atomic_store(&raw_worker_started, 0);
        if (pthread_create(&thread, NULL, raw_exit_survivor, &raw_pipes) != 0)
            _exit(92);
        while (!atomic_load_explicit(&raw_worker_started, memory_order_acquire))
            ;
        syscall(SYS_exit, 41);
        _exit(93);
    }
    close(ready[1]);
    close(command[0]);
    if (read(ready[0], &byte, 1) != 1 || byte != 'R') {
        terminate_child(pid);
        return failf("surviving thread did not start");
    }
    usleep(30000);
    if (waitpid(pid, &status, WNOHANG) != 0) {
        terminate_child(pid);
        return failf("SYS_exit terminated the whole process");
    }
    byte = 'X';
    if (write(command[1], &byte, 1) != 1) {
        terminate_child(pid);
        return failf("could not release surviving thread");
    }
    if (wait_bounded(pid, &status, 200) != pid || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 37) {
        terminate_child(pid);
        return failf("last thread did not terminate process normally");
    }
    close(ready[0]);
    close(command[1]);
    return 0;
}

struct mask_result {
    int block;
    int member;
    int error;
};

static void *mask_worker(void *opaque)
{
    struct mask_result *result = opaque;
    sigset_t set;
    sigset_t current;

    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    result->error = pthread_sigmask(result->block ? SIG_BLOCK : SIG_UNBLOCK,
                                    &set, NULL);
    if (result->error != 0)
        return NULL;
    result->error = pthread_sigmask(SIG_SETMASK, NULL, &current);
    if (result->error != 0)
        return NULL;
    result->member = sigismember(&current, SIGUSR1);
    return NULL;
}

static int test_thread_masks_independent(void)
{
    pthread_t first;
    pthread_t second;
    struct mask_result a = { 1, -1, 0 };
    struct mask_result b = { 0, -1, 0 };
    sigset_t current;

    if (pthread_create(&first, NULL, mask_worker, &a) != 0)
        return failf("pthread_create failed");
    if (pthread_create(&second, NULL, mask_worker, &b) != 0) {
        (void)pthread_join(first, NULL);
        return failf("pthread_create failed");
    }
    if (pthread_join(first, NULL) != 0 || pthread_join(second, NULL) != 0)
        return failf("pthread_join failed");
    if (pthread_sigmask(SIG_SETMASK, NULL, &current) != 0)
        return failf("pthread_sigmask query failed");
    if (a.error != 0 || b.error != 0 || a.member != 1 || b.member != 0 ||
        sigismember(&current, SIGUSR1) != 0)
        return failf("pthread signal masks were not independent");
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "unique TIDs and shared getpid", test_thread_ids },
    { "TLS and pthread return/join", test_tls_and_return_join },
    { "process-private mutex", test_process_private_mutex },
    { "process-private condition", test_process_private_condition },
    { "process-private barrier", test_process_private_barrier },
    { "raw SYS_exit affects only caller", test_raw_exit_only_caller },
    { "independent thread signal masks", test_thread_masks_independent },
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
    printf("SUMMARY threads: %d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
