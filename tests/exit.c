/*
 * process/thread exit test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_exit tests/exit.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SYS_exit
#define SYS_exit 1
#endif
#ifndef SYS_exit_group
#define SYS_exit_group 252
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

static int test_exit_status(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0)
        exit(42);
    if (!wait_status(pid, 42))
        return failf("exit(42) status was not observed");
    return 0;
}

static int test__exit_status(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0)
        _exit(73);
    if (!wait_status(pid, 73))
        return failf("_exit(73) status was not observed");
    return 0;
}

static void *endless_worker(void *unused)
{
    (void)unused;
    for (;;)
        usleep(10000);
    return NULL;
}

static int test_exit_group(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        pthread_t thread;

        if (pthread_create(&thread, NULL, endless_worker, NULL) != 0)
            _exit(90);
        usleep(10000);
        syscall(SYS_exit_group, 55);
        _exit(91);
    }
    if (!wait_status(pid, 55))
        return failf("exit_group did not terminate every thread/status 55");
    return 0;
}

static _Atomic int last_thread_started;
static int last_ready_write;
static int last_command_read;

static void *last_thread_worker(void *unused)
{
    char byte = 'R';

    (void)unused;
    atomic_store_explicit(&last_thread_started, 1, memory_order_release);
    if (write(last_ready_write, &byte, 1) != 1)
        syscall(SYS_exit, 90);
    if (read(last_command_read, &byte, 1) != 1)
        syscall(SYS_exit, 91);
    syscall(SYS_exit, 29);
    return NULL;
}

static int test_last_thread_lifetime(void)
{
    pid_t pid;
    int status = 0;
    int ready[2];
    int command[2];
    int leader_notice[2];
    char byte;

    if (pipe(ready) != 0 || pipe(command) != 0 || pipe(leader_notice) != 0)
        return failf("pipe failed: %s", strerror(errno));
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        pthread_t thread;

        close(ready[0]);
        close(command[1]);
        close(leader_notice[0]);
        last_ready_write = ready[1];
        last_command_read = command[0];
        atomic_store(&last_thread_started, 0);
        if (pthread_create(&thread, NULL, last_thread_worker, NULL) != 0)
            _exit(90);
        while (!atomic_load_explicit(&last_thread_started,
                                     memory_order_acquire))
            ;
        byte = 'L';
        if (write(leader_notice[1], &byte, 1) != 1)
            _exit(92);
        syscall(SYS_exit, 17);
        _exit(93);
    }
    close(ready[1]);
    close(command[0]);
    close(leader_notice[1]);
    if (read(ready[0], &byte, 1) != 1 || byte != 'R' ||
        read(leader_notice[0], &byte, 1) != 1 || byte != 'L') {
        terminate_child(pid);
        return failf("last-thread setup handshake failed");
    }
    usleep(20000);
    if (waitpid(pid, &status, WNOHANG) != 0) {
        terminate_child(pid);
        return failf("process died before its last thread exited");
    }
    byte = 'X';
    if (write(command[1], &byte, 1) != 1) {
        terminate_child(pid);
        return failf("could not release last thread");
    }
    if (wait_bounded(pid, &status, 200) != pid || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 29) {
        terminate_child(pid);
        return failf("last-thread process termination was invalid");
    }
    close(ready[0]);
    close(command[1]);
    close(leader_notice[0]);
    return 0;
}

static int test_descriptor_cleanup_pipe_eof(void)
{
    int fd[2];
    pid_t pid;
    char byte;

    if (pipe(fd) != 0)
        return failf("pipe failed: %s", strerror(errno));
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        close(fd[0]);
        usleep(50000);
        _exit(0);
    }
    close(fd[1]);
    errno = 0;
    if (read(fd[0], &byte, 1) != 0) {
        terminate_child(pid);
        return failf("pipe did not reach EOF after writer process exit");
    }
    close(fd[0]);
    if (!wait_status(pid, 0))
        return failf("descriptor-cleanup child status was wrong");
    return 0;
}

static int test_zombie_reaping_and_echild(void)
{
    int handshake[2];
    pid_t pid;
    pid_t got;
    int status = 0;
    char byte;

    if (pipe(handshake) != 0)
        return failf("pipe failed: %s", strerror(errno));
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        close(handshake[0]);
        byte = 'Z';
        if (write(handshake[1], &byte, 1) != 1)
            _exit(90);
        _exit(9);
    }
    close(handshake[1]);
    if (read(handshake[0], &byte, 1) != 1 || byte != 'Z' ||
        read(handshake[0], &byte, 1) != 0) {
        terminate_child(pid);
        return failf("child-exit handshake failed");
    }
    close(handshake[0]);
    got = waitpid(pid, &status, WNOHANG);
    if (got != pid || !WIFEXITED(status) || WEXITSTATUS(status) != 9)
        return failf("zombie was not retained/reaped with status 9");
    errno = 0;
    if (waitpid(pid, &status, WNOHANG) != -1 || errno != ECHILD)
        return failf("second wait did not return ECHILD");
    errno = 0;
    if (waitpid(-1, &status, WNOHANG) != -1 || errno != ECHILD)
        return failf("wait with no children did not return ECHILD");
    return 0;
}

#define TEARDOWN_THREADS 8
static _Atomic unsigned teardown_started;

static void *teardown_worker(void *unused)
{
    (void)unused;
    atomic_fetch_add_explicit(&teardown_started, 1, memory_order_release);
    for (;;)
        usleep(1000);
    return NULL;
}

static int test_concurrent_thread_teardown(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        pthread_t threads[TEARDOWN_THREADS];
        unsigned i;

        atomic_store(&teardown_started, 0);
        for (i = 0; i < TEARDOWN_THREADS; i++) {
            if (pthread_create(&threads[i], NULL, teardown_worker, NULL) != 0)
                _exit(90);
        }
        while (atomic_load_explicit(&teardown_started,
                                    memory_order_acquire) != TEARDOWN_THREADS)
            usleep(1000);
        syscall(SYS_exit_group, 66);
        _exit(91);
    }
    if (!wait_status(pid, 66))
        return failf("concurrent thread-group teardown failed");
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "exit status", test_exit_status },
    { "_exit status", test__exit_status },
    { "exit_group terminates threads", test_exit_group },
    { "last-thread process lifetime", test_last_thread_lifetime },
    { "descriptor cleanup produces pipe EOF", test_descriptor_cleanup_pipe_eof },
    { "zombie reaping and ECHILD", test_zombie_reaping_and_echild },
    { "concurrent thread teardown", test_concurrent_thread_teardown },
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
    printf("SUMMARY exit: %d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
