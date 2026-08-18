/*
 * futex + pthread test suite
 *
 * Covers:
 *   FUTEX_WAIT
 *   FUTEX_WAKE
 *   FUTEX_WAIT EAGAIN
 *   FUTEX_WAIT timeout
 *   wake-one
 *   wake-all
 *   pthread_join
 *   pthread_mutex contention
 *   pthread_cond_signal
 *   pthread_cond_broadcast
 *
 * Build:
 *   zig cc -target x86-linux-musl -static \
 *      -o test_futex test_futex.c -lpthread
 */

#define _GNU_SOURCE

#include <errno.h>
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

/* ---------------------------------------------------------- */
/* result tracking                                              */
/* ---------------------------------------------------------- */

static int g_passed;
static int g_failed;

static void ok(const char *name)
{
    printf("  PASS  %s\n", name);
    g_passed++;
}

static void nok(const char *name, const char *why)
{
    printf("  FAIL  %s [%s]\n", name, why);
    g_failed++;
}

#define CHECK(cond,name,why) \
    do { if (cond) ok(name); else nok(name,why); } while (0)

/* ---------------------------------------------------------- */
/* futex helpers                                                */
/* ---------------------------------------------------------- */

static int futex_wait(int *uaddr, int expected)
{
    return syscall(SYS_futex,
                   uaddr,
                   FUTEX_WAIT,
                   expected,
                   NULL,
                   NULL,
                   0);
}

static int futex_wait_timeout(int *uaddr,
                              int expected,
                              const struct timespec *ts)
{
    return syscall(SYS_futex,
                   uaddr,
                   FUTEX_WAIT,
                   expected,
                   ts,
                   NULL,
                   0);
}

static int futex_wake(int *uaddr, int nr)
{
    return syscall(SYS_futex,
                   uaddr,
                   FUTEX_WAKE,
                   nr,
                   NULL,
                   NULL,
                   0);
}

/* ---------------------------------------------------------- */
/* 1. basic FUTEX_WAIT / FUTEX_WAKE                            */
/* ---------------------------------------------------------- */

static volatile int fut1;
static volatile int fut1_woke;

static void *waiter1(void *arg)
{
    (void)arg;

    futex_wait((int *)&fut1, 0);

    fut1_woke = 1;
    return NULL;
}

static void test_futex_wait_wake(void)
{
    puts("\n[ 1. FUTEX_WAIT/FUTEX_WAKE ]");

    fut1 = 0;
    fut1_woke = 0;

    pthread_t t;
    pthread_create(&t, NULL, waiter1, NULL);

    usleep(20000);

    fut1 = 1;

    int r = futex_wake((int *)&fut1, 1);

    pthread_join(t, NULL);

    CHECK(r == 1,
          "wake returns 1",
          "wrong wake count");

    CHECK(fut1_woke,
          "waiter resumed",
          "thread stayed asleep");
}

/* ---------------------------------------------------------- */
/* 2. EAGAIN                                                   */
/* ---------------------------------------------------------- */

static void test_futex_eagain(void)
{
    puts("\n[ 2. FUTEX_WAIT EAGAIN ]");

    int fut = 1;

    errno = 0;

    int r = futex_wait(&fut, 0);

    CHECK(r == -1 && errno == EAGAIN,
          "value mismatch returns EAGAIN",
          "wrong return");
}

/* ---------------------------------------------------------- */
/* 3. timeout                                                  */
/* ---------------------------------------------------------- */

static void test_futex_timeout(void)
{
    puts("\n[ 3. FUTEX_WAIT timeout ]");

    int fut = 0;

    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 50000000;

    errno = 0;

    int r = futex_wait_timeout(&fut, 0, &ts);

    CHECK(r == -1 && errno == ETIMEDOUT,
          "timeout -> ETIMEDOUT",
          "wrong result");
}

/* ---------------------------------------------------------- */
/* 4. wake one waiter                                          */
/* ---------------------------------------------------------- */

static volatile int fut4;
static volatile int wake_one_count;

static void *waiter4(void *arg)
{
    (void)arg;

    futex_wait((int *)&fut4, 0);

    __sync_fetch_and_add(&wake_one_count, 1);

    return NULL;
}

static void test_wake_one(void)
{
    puts("\n[ 4. wake one ]");

    pthread_t t1, t2, t3;

    fut4 = 0;
    wake_one_count = 0;

    pthread_create(&t1, NULL, waiter4, NULL);
    pthread_create(&t2, NULL, waiter4, NULL);
    pthread_create(&t3, NULL, waiter4, NULL);

    usleep(20000);

    fut4 = 1;

    int r = futex_wake((int *)&fut4, 1);

    usleep(20000);

    CHECK(r == 1,
          "wake count == 1",
          "wrong count");

    CHECK(wake_one_count == 1,
          "one waiter resumed",
          "wrong number resumed");

    futex_wake((int *)&fut4, INT_MAX);

    pthread_join(t1,NULL);
    pthread_join(t2,NULL);
    pthread_join(t3,NULL);
}

/* ---------------------------------------------------------- */
/* 5. wake all                                                 */
/* ---------------------------------------------------------- */

static volatile int fut5;
static volatile int wake_all_count;

static void *waiter5(void *arg)
{
    (void)arg;

    futex_wait((int *)&fut5, 0);

    __sync_fetch_and_add(&wake_all_count, 1);

    return NULL;
}

static void test_wake_all(void)
{
    puts("\n[ 5. wake all ]");

    pthread_t t1, t2, t3;

    fut5 = 0;
    wake_all_count = 0;

    pthread_create(&t1,NULL,waiter5,NULL);
    pthread_create(&t2,NULL,waiter5,NULL);
    pthread_create(&t3,NULL,waiter5,NULL);

    usleep(20000);

    fut5 = 1;

    int r = futex_wake((int *)&fut5, INT_MAX);

    pthread_join(t1,NULL);
    pthread_join(t2,NULL);
    pthread_join(t3,NULL);

    CHECK(r == 3,
          "wake-all reports 3",
          "wrong wake count");

    CHECK(wake_all_count == 3,
          "all waiters resumed",
          "not all resumed");
}

/* ---------------------------------------------------------- */
/* 6. pthread_join                                             */
/* ---------------------------------------------------------- */

static void *join_worker(void *arg)
{
    (void)arg;
    return (void *)0x1234;
}

static void test_pthread_join(void)
{
    puts("\n[ 6. pthread_join ]");

    pthread_t t;

    pthread_create(&t,NULL,join_worker,NULL);

    void *ret = NULL;

    int r = pthread_join(t,&ret);

    CHECK(r == 0,
          "pthread_join succeeds",
          "join failed");

    CHECK(ret == (void *)0x1234,
          "return value preserved",
          "wrong retval");
}

/* ---------------------------------------------------------- */
/* 7. mutex contention                                         */
/* ---------------------------------------------------------- */

static pthread_mutex_t mtx =
    PTHREAD_MUTEX_INITIALIZER;

static volatile int mutex_seen;

static void *mutex_thread(void *arg)
{
    (void)arg;

    pthread_mutex_lock(&mtx);

    mutex_seen = 1;

    pthread_mutex_unlock(&mtx);

    return NULL;
}

static void test_mutex_contention(void)
{
    puts("\n[ 7. pthread_mutex ]");

    mutex_seen = 0;

    pthread_mutex_lock(&mtx);

    pthread_t t;
    pthread_create(&t,NULL,mutex_thread,NULL);

    usleep(20000);

    CHECK(!mutex_seen,
          "thread blocked on mutex",
          "lock did not block");

    pthread_mutex_unlock(&mtx);

    pthread_join(t,NULL);

    CHECK(mutex_seen,
          "thread acquires after unlock",
          "never acquired");
}

/* ---------------------------------------------------------- */
/* 8. cond signal                                              */
/* ---------------------------------------------------------- */

static pthread_mutex_t cv_mtx =
    PTHREAD_MUTEX_INITIALIZER;

static pthread_cond_t cv =
    PTHREAD_COND_INITIALIZER;

static volatile int cv_ready;
static volatile int cv_seen;

static void *cv_waiter(void *arg)
{
    (void)arg;

    pthread_mutex_lock(&cv_mtx);

    while (!cv_ready)
        pthread_cond_wait(&cv, &cv_mtx);

    cv_seen = 1;

    pthread_mutex_unlock(&cv_mtx);

    return NULL;
}

static void test_cond_signal(void)
{
    puts("\n[ 8. pthread_cond_signal ]");

    cv_ready = 0;
    cv_seen = 0;

    pthread_t t;
    pthread_create(&t,NULL,cv_waiter,NULL);

    usleep(20000);

    pthread_mutex_lock(&cv_mtx);

    cv_ready = 1;

    pthread_cond_signal(&cv);

    pthread_mutex_unlock(&cv_mtx);

    pthread_join(t,NULL);

    CHECK(cv_seen,
          "cond signal wakes waiter",
          "waiter never resumed");
}

/* ---------------------------------------------------------- */
/* 9. cond broadcast                                           */
/* ---------------------------------------------------------- */

static volatile int bc_ready;
static volatile int bc_count;

static void *bc_waiter(void *arg)
{
    (void)arg;

    pthread_mutex_lock(&cv_mtx);

    while (!bc_ready)
        pthread_cond_wait(&cv, &cv_mtx);

    __sync_fetch_and_add(&bc_count,1);

    pthread_mutex_unlock(&cv_mtx);

    return NULL;
}

static void test_cond_broadcast(void)
{
    puts("\n[ 9. pthread_cond_broadcast ]");

    bc_ready = 0;
    bc_count = 0;

    pthread_t t1,t2,t3;

    pthread_create(&t1,NULL,bc_waiter,NULL);
    pthread_create(&t2,NULL,bc_waiter,NULL);
    pthread_create(&t3,NULL,bc_waiter,NULL);

    usleep(20000);

    pthread_mutex_lock(&cv_mtx);

    bc_ready = 1;

    pthread_cond_broadcast(&cv);

    pthread_mutex_unlock(&cv_mtx);

    pthread_join(t1,NULL);
    pthread_join(t2,NULL);
    pthread_join(t3,NULL);

    CHECK(bc_count == 3,
          "broadcast wakes all waiters",
          "not all resumed");
}

/* ---------------------------------------------------------- */
/* 10. ping-pong stress                                        */
/* ---------------------------------------------------------- */

static volatile int ping;
static volatile int pong;

static void *pong_thread(void *arg)
{
    (void)arg;

    for (int i = 0; i < 1000; i++) {

        while (!ping)
            futex_wait((int *)&ping, 0);

        ping = 0;

        pong = 1;
        futex_wake((int *)&pong, 1);
    }

    return NULL;
}

static void test_ping_pong(void)
{
    puts("\n[ 10. ping-pong stress ]");

    ping = 0;
    pong = 0;

    pthread_t t;
    pthread_create(&t,NULL,pong_thread,NULL);

    for (int i = 0; i < 1000; i++) {

        ping = 1;
        futex_wake((int *)&ping, 1);

        while (!pong)
            futex_wait((int *)&pong, 0);

        pong = 0;
    }

    pthread_join(t,NULL);

    CHECK(1,
          "1000 ping-pong iterations completed",
          "unexpected failure");
}

/* ---------------------------------------------------------- */
/* main                                                        */
/* ---------------------------------------------------------- */

int main(void)
{
    puts("=== futex test suite ===");

    test_futex_wait_wake();
    test_futex_eagain();
    test_futex_timeout();
    test_wake_one();
    test_wake_all();
    test_pthread_join();
    test_mutex_contention();
    test_cond_signal();
    test_cond_broadcast();
    test_ping_pong();

    printf("\n=== %d passed, %d failed ===\n",
           g_passed,
           g_failed);

    return g_failed ? 1 : 0;
}

