/*
 * fork test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_fork tests/fork.c
 *
 * Reading the running image resolves argv[0] through cwd and PATH. If neither
 * works, invoke this suite with an explicit executable pathname.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static const char *self_path;
static char self_path_storage[PATH_MAX];

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

static const char *resolve_self_path(const char *argv0)
{
    const char *path;

    if (strchr(argv0, '/') != NULL)
        return argv0;
    if (getcwd(self_path_storage, sizeof(self_path_storage)) != NULL) {
        size_t used = strlen(self_path_storage);

        if (used + 1 + strlen(argv0) + 1 <= sizeof(self_path_storage)) {
            self_path_storage[used++] = '/';
            strcpy(self_path_storage + used, argv0);
            if (access(self_path_storage, R_OK) == 0)
                return self_path_storage;
        }
    }
    path = getenv("PATH");
    while (path != NULL && *path != '\0') {
        const char *end = strchr(path, ':');
        size_t dir_len = end != NULL ? (size_t)(end - path) : strlen(path);
        size_t name_len = strlen(argv0);

        if (dir_len + 1 + name_len + 1 <= sizeof(self_path_storage)) {
            memcpy(self_path_storage, path, dir_len);
            self_path_storage[dir_len] = '/';
            memcpy(self_path_storage + dir_len + 1, argv0, name_len + 1);
            if (access(self_path_storage, R_OK) == 0)
                return self_path_storage;
        }
        path = end != NULL ? end + 1 : NULL;
    }
    return argv0;
}

struct pid_report {
    pid_t fork_result;
    pid_t pid;
    pid_t ppid;
};

static int test_return_and_pid_relationships(void)
{
    int fd[2];
    struct pid_report report;
    pid_t parent = getpid();
    pid_t child;

    if (pipe(fd) != 0)
        return failf("pipe failed: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork failed: %s", strerror(errno));
    if (child == 0) {
        ssize_t n;

        close(fd[0]);
        report.fork_result = child;
        report.pid = getpid();
        report.ppid = getppid();
        n = write(fd[1], &report, sizeof(report));
        _exit(n == (ssize_t)sizeof(report) ? 0 : 2);
    }
    close(fd[1]);
    if (read(fd[0], &report, sizeof(report)) != (ssize_t)sizeof(report)) {
        terminate_child(child);
        return failf("could not read child PID report");
    }
    close(fd[0]);
    if (!wait_status(child, 0))
        return failf("PID-report child failed");
    if (report.fork_result != 0 || report.pid != child ||
        report.ppid != parent || child == parent)
        return failf("fork/PID relationship was inconsistent");
    return 0;
}

static int test_memory_isolation(void)
{
    volatile uint32_t value = 0x11223344u;
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        if (value != 0x11223344u)
            _exit(2);
        value = 0xaabbccddu;
        _exit(value == 0xaabbccddu ? 0 : 3);
    }
    if (!wait_status(pid, 0))
        return failf("memory child failed");
    if (value != 0x11223344u)
        return failf("child write changed parent memory");
    return 0;
}

static int test_inherited_directional_pipes(void)
{
    int to_child[2];
    int from_child[2];
    pid_t pid;
    char request = 'Q';
    char reply = 0;

    if (pipe(to_child) != 0 || pipe(from_child) != 0)
        return failf("pipe failed: %s", strerror(errno));
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char byte;

        close(to_child[1]);
        close(from_child[0]);
        if (read(to_child[0], &byte, 1) != 1 || byte != 'Q')
            _exit(2);
        byte = 'A';
        if (write(from_child[1], &byte, 1) != 1)
            _exit(3);
        close(to_child[0]);
        close(from_child[1]);
        _exit(0);
    }
    close(to_child[0]);
    close(from_child[1]);
    if (write(to_child[1], &request, 1) != 1 ||
        read(from_child[0], &reply, 1) != 1) {
        terminate_child(pid);
        return failf("parent/child pipe exchange failed");
    }
    close(to_child[1]);
    close(from_child[0]);
    if (reply != 'A' || !wait_status(pid, 0))
        return failf("inherited descriptors were not directional");
    return 0;
}

static int test_inherited_file_offset(void)
{
    int shared;
    int reference;
    int report[2];
    unsigned char expected[3];
    unsigned char first;
    unsigned char child_byte;
    unsigned char parent_byte;
    pid_t pid;

    shared = open(self_path, O_RDONLY);
    reference = open(self_path, O_RDONLY);
    if (shared < 0 || reference < 0)
        return failf("open self failed: %s", strerror(errno));
    if (read(reference, expected, sizeof(expected)) != (ssize_t)sizeof(expected) ||
        read(shared, &first, 1) != 1)
        return failf("could not read self executable");
    if (first != expected[0])
        return failf("reference reads disagreed");
    if (pipe(report) != 0)
        return failf("report pipe failed: %s", strerror(errno));

    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        close(report[0]);
        if (read(shared, &child_byte, 1) != 1 ||
            write(report[1], &child_byte, 1) != 1)
            _exit(2);
        _exit(0);
    }
    close(report[1]);
    if (read(report[0], &child_byte, 1) != 1) {
        terminate_child(pid);
        return failf("child did not report its byte");
    }
    if (!wait_status(pid, 0) || read(shared, &parent_byte, 1) != 1)
        return failf("shared-offset read failed");
    close(report[0]);
    close(shared);
    close(reference);
    if (child_byte != expected[1] || parent_byte != expected[2])
        return failf("open-file offset was not shared across fork");
    return 0;
}

static int test_many_children_and_reaping(void)
{
    enum { CHILDREN = 16 };
    pid_t pids[CHILDREN];
    int live[CHILDREN] = { 0 };
    int i;

    for (i = 0; i < CHILDREN; i++) {
        pids[i] = fork();
        if (pids[i] < 0) {
            int saved_errno = errno;
            int j;

            for (j = 0; j < i; j++) {
                if (live[j])
                    (void)kill(pids[j], SIGKILL);
            }
            for (j = 0; j < i; j++) {
                int status;

                if (live[j])
                    (void)wait_bounded(pids[j], &status, 100);
            }
            return failf("fork %d failed: %s", i, strerror(saved_errno));
        }
        if (pids[i] == 0)
            _exit(i);
        live[i] = 1;
    }
    for (i = CHILDREN - 1; i >= 0; i--) {
        int status;
        pid_t got = wait_bounded(pids[i], &status, 200);

        if (got == pids[i])
            live[i] = 0;
        else if (got < 0 && errno == ECHILD)
            live[i] = 0;
        else if (got == 0) {
            terminate_child(pids[i]);
            live[i] = 0;
        }
        if (got != pids[i] || !WIFEXITED(status) ||
            WEXITSTATUS(status) != i) {
            int j;

            for (j = 0; j < CHILDREN; j++) {
                if (live[j])
                    (void)kill(pids[j], SIGKILL);
            }
            for (j = 0; j < CHILDREN; j++) {
                if (live[j])
                    (void)wait_bounded(pids[j], &status, 100);
            }
            return failf("child %d had wrong PID/status", i);
        }
    }
    errno = 0;
    if (waitpid(-1, NULL, WNOHANG) != -1 || errno != ECHILD)
        return failf("all children were not reaped");
    return 0;
}

static _Atomic int background_run;
static _Atomic unsigned background_ticks;

static void *background_worker(void *unused)
{
    (void)unused;
    while (atomic_load_explicit(&background_run, memory_order_acquire)) {
        atomic_fetch_add_explicit(&background_ticks, 1, memory_order_relaxed);
        usleep(1000);
    }
    return NULL;
}

static int test_fork_with_background_thread(void)
{
    pthread_t thread;
    pid_t pid;
    unsigned before;
    int rc;

    atomic_store(&background_run, 1);
    atomic_store(&background_ticks, 0);
    rc = pthread_create(&thread, NULL, background_worker, NULL);
    if (rc != 0)
        return failf("pthread_create failed: %s", strerror(rc));
    while (atomic_load(&background_ticks) == 0)
        usleep(1000);
    before = atomic_load(&background_ticks);

    pid = fork();
    if (pid < 0) {
        atomic_store_explicit(&background_run, 0, memory_order_release);
        (void)pthread_join(thread, NULL);
        return failf("fork with background thread failed: %s", strerror(errno));
    }
    if (pid == 0)
        _exit(0); /* Only an async-signal-safe operation after fork. */
    if (!wait_status(pid, 0)) {
        atomic_store_explicit(&background_run, 0, memory_order_release);
        (void)pthread_join(thread, NULL);
        return failf("multithreaded-fork child failed");
    }
    usleep(10000);
    atomic_store_explicit(&background_run, 0, memory_order_release);
    rc = pthread_join(thread, NULL);
    if (rc != 0)
        return failf("pthread_join failed: %s", strerror(rc));
    if (atomic_load(&background_ticks) <= before)
        return failf("parent background thread stopped across fork");
    return 0;
}

static int test_child_status(void)
{
    pid_t pid = fork();
    int status;

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0)
        _exit(73);
    if (wait_bounded(pid, &status, 200) != pid) {
        terminate_child(pid);
        return failf("waitpid failed: %s", strerror(errno));
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 73 ||
        WIFSIGNALED(status) || WIFSTOPPED(status))
        return failf("child status word decoded incorrectly");
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "fork return and PID relationships", test_return_and_pid_relationships },
    { "private memory isolation", test_memory_isolation },
    { "inherited directional pipes", test_inherited_directional_pipes },
    { "inherited open-file offset", test_inherited_file_offset },
    { "many children and complete reaping", test_many_children_and_reaping },
    { "fork while pthread runs", test_fork_with_background_thread },
    { "child exit status", test_child_status },
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

int main(int argc, char **argv)
{
    int passed = 0;
    int failed = 0;
    size_t i;

    (void)argc;
    /* If cwd/PATH cannot resolve a bare argv[0], invoke with a pathname. */
    self_path = resolve_self_path(argv[0]);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_test(&tests[i], &passed, &failed);
    printf("SUMMARY fork: %d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
