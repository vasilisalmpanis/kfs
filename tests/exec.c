/*
 * execve test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_exec tests/exec.c
 *
 * Self-exec resolves argv[0] through cwd and PATH without /proc. If neither
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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_SKIP 77
#ifndef SYS_exit
#define SYS_exit 1
#endif

static const char *self_path;
static char self_path_storage[PATH_MAX];
static _Atomic int exec_sibling_ready;

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

static int parse_fd(const char *text)
{
    char *end;
    long value = strtol(text, &end, 10);

    if (*text == '\0' || *end != '\0' || value < 0 || value > 0x7fffffffL)
        return -1;
    return (int)value;
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
            if (access(self_path_storage, X_OK) == 0)
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
            if (access(self_path_storage, X_OK) == 0)
                return self_path_storage;
        }
        path = end != NULL ? end + 1 : NULL;
    }
    return argv0;
}

static int child_mode(int argc, char **argv)
{
    if (argc < 2)
        return -1;
    if (strcmp(argv[1], "--exec-argv-env") == 0) {
        const char *mark = getenv("KFS_EXEC_MARK");

        return argc == 4 && strcmp(argv[2], "alpha") == 0 &&
               strcmp(argv[3], "two words") == 0 && mark != NULL &&
               strcmp(mark, "preserved-value") == 0 ? 42 : 2;
    }
    if (strcmp(argv[1], "--exec-replaced") == 0)
        return argc == 3 && strcmp(argv[2], "new-image") == 0 ? 61 : 3;
    if (strcmp(argv[1], "--exec-fd-probe") == 0) {
        int closed_fd;
        int open_fd;
        int closed_result;
        int closed_errno;

        if (argc != 4)
            return 4;
        closed_fd = parse_fd(argv[2]);
        open_fd = parse_fd(argv[3]);
        if (closed_fd < 0 || open_fd < 0)
            return 5;
        errno = 0;
        closed_result = fcntl(closed_fd, F_GETFD);
        closed_errno = errno;
        if (closed_result != -1 || closed_errno != EBADF)
            return 6;
        if (fcntl(open_fd, F_GETFD) < 0)
            return 7;
        return 0;
    }
    if (strcmp(argv[1], "--exec-pipe2-probe") == 0) {
        int first;
        int second;
        int rc1;
        int err1;
        int rc2;
        int err2;

        if (argc != 4)
            return 8;
        first = parse_fd(argv[2]);
        second = parse_fd(argv[3]);
        errno = 0;
        rc1 = fcntl(first, F_GETFD);
        err1 = errno;
        errno = 0;
        rc2 = fcntl(second, F_GETFD);
        err2 = errno;
        return rc1 == -1 && err1 == EBADF && rc2 == -1 && err2 == EBADF
                   ? 0
                   : 9;
    }
    if (strcmp(argv[1], "--exec-signal-probe") == 0) {
        struct sigaction usr1;
        struct sigaction usr2;
        sigset_t mask;

        if (sigaction(SIGUSR1, NULL, &usr1) != 0 ||
            sigaction(SIGUSR2, NULL, &usr2) != 0 ||
            pthread_sigmask(SIG_SETMASK, NULL, &mask) != 0)
            return 10;
        if (usr1.sa_handler != SIG_DFL)
            return 11;
        if (usr2.sa_handler != SIG_IGN)
            return 12;
        if (sigismember(&mask, SIGTERM) != 1)
            return 13;
        return 0;
    }
    if (strcmp(argv[1], "--exec-thread-probe") == 0) {
        syscall(SYS_exit, 64);
        return 14;
    }
    return -1;
}

static int wait_expected(pid_t pid, int expected)
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

static int test_argv_and_environment(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char *const args[] = {
            (char *)self_path, "--exec-argv-env", "alpha", "two words", NULL
        };
        char *const env[] = {
            "KFS_EXEC_MARK=preserved-value", "SECOND=value", NULL
        };

        execve(self_path, args, env);
        _exit(100);
    }
    if (!wait_expected(pid, 42))
        return failf("self-exec did not preserve argv/environment");
    return 0;
}

static int test_success_replaces_image(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char *const args[] = {
            (char *)self_path, "--exec-replaced", "new-image", NULL
        };
        char *const env[] = { "KFS_EXEC_IMAGE=new", NULL };

        execve(self_path, args, env);
        _exit(99);
    }
    if (!wait_expected(pid, 61))
        return failf("successful exec did not replace the old image");
    return 0;
}

static int test_failed_exec_keeps_image(void)
{
    char *const args[] = { "/definitely/not/a/kfs/program", NULL };
    char *const env[] = { "X=1", NULL };
    volatile int marker = 0x1234;

    errno = 0;
    if (execve(args[0], args, env) != -1)
        return failf("execve of missing path succeeded");
    if (errno != ENOENT)
        return failf("missing exec returned errno %d, expected ENOENT", errno);
    marker++;
    if (marker != 0x1235)
        return failf("old image did not continue after failed exec");
    return 0;
}

static int test_fcntl_cloexec(void)
{
    int fd[2];
    pid_t pid;

    if (pipe(fd) != 0)
        return failf("pipe failed: %s", strerror(errno));
    if (fcntl(fd[0], F_SETFD, FD_CLOEXEC) != 0 ||
        (fcntl(fd[0], F_GETFD) & FD_CLOEXEC) == 0)
        return failf("fcntl could not set FD_CLOEXEC");
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char closed_text[24];
        char open_text[24];
        char *args[5];
        char *const env[] = { "KFS_EXEC_FD=fcntl", NULL };

        snprintf(closed_text, sizeof(closed_text), "%d", fd[0]);
        snprintf(open_text, sizeof(open_text), "%d", fd[1]);
        args[0] = (char *)self_path;
        args[1] = "--exec-fd-probe";
        args[2] = closed_text;
        args[3] = open_text;
        args[4] = NULL;
        execve(self_path, args, env);
        _exit(100);
    }
    close(fd[0]);
    close(fd[1]);
    if (!wait_expected(pid, 0))
        return failf("fcntl FD_CLOEXEC state was wrong after exec");
    return 0;
}

static int test_pipe2_cloexec(void)
{
    int fd[2];
    pid_t pid;

    if (pipe2(fd, O_CLOEXEC) != 0) {
        if (errno == ENOSYS)
            return TEST_SKIP;
        return failf("pipe2(O_CLOEXEC) failed: %s", strerror(errno));
    }
    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char first[24];
        char second[24];
        char *args[5];
        char *const env[] = { "KFS_EXEC_FD=pipe2", NULL };

        snprintf(first, sizeof(first), "%d", fd[0]);
        snprintf(second, sizeof(second), "%d", fd[1]);
        args[0] = (char *)self_path;
        args[1] = "--exec-pipe2-probe";
        args[2] = first;
        args[3] = second;
        args[4] = NULL;
        execve(self_path, args, env);
        _exit(100);
    }
    close(fd[0]);
    close(fd[1]);
    if (!wait_expected(pid, 0))
        return failf("pipe2 O_CLOEXEC descriptors survived exec");
    return 0;
}

static void caught_handler(int sig)
{
    (void)sig;
}

static int test_signal_exec_semantics(void)
{
    struct sigaction caught;
    struct sigaction ignored;
    sigset_t blocked;
    pid_t pid;

    memset(&caught, 0, sizeof(caught));
    caught.sa_handler = caught_handler;
    sigemptyset(&caught.sa_mask);
    memset(&ignored, 0, sizeof(ignored));
    ignored.sa_handler = SIG_IGN;
    sigemptyset(&ignored.sa_mask);
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM);
    if (sigaction(SIGUSR1, &caught, NULL) != 0 ||
        sigaction(SIGUSR2, &ignored, NULL) != 0 ||
        pthread_sigmask(SIG_BLOCK, &blocked, NULL) != 0) {
        if (errno == ENOSYS)
            return TEST_SKIP;
        return failf("signal setup failed: %s", strerror(errno));
    }

    pid = fork();
    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char *const args[] = {
            (char *)self_path, "--exec-signal-probe", NULL
        };
        char *const env[] = { "KFS_EXEC_SIGNAL=1", NULL };

        execve(self_path, args, env);
        _exit(100);
    }
    (void)pthread_sigmask(SIG_UNBLOCK, &blocked, NULL);
    if (!wait_expected(pid, 0))
        return failf("exec signal disposition/mask semantics failed");
    return 0;
}

static void *exec_sibling(void *unused)
{
    (void)unused;
    atomic_store_explicit(&exec_sibling_ready, 1, memory_order_release);
    for (;;)
        usleep(10000);
    return NULL;
}

static int test_multithreaded_exec_removes_siblings(void)
{
    pid_t pid = fork();
    int status = 0;
    pid_t got;

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        pthread_t sibling;
        char *const args[] = {
            (char *)self_path, "--exec-thread-probe", NULL
        };
        char *const env[] = { "KFS_EXEC_THREADS=1", NULL };
        unsigned tick;

        atomic_store(&exec_sibling_ready, 0);
        if (pthread_create(&sibling, NULL, exec_sibling, NULL) != 0)
            _exit(90);
        for (tick = 0; tick < 200 &&
             !atomic_load_explicit(&exec_sibling_ready, memory_order_acquire);
             tick++)
            usleep(1000);
        if (!atomic_load_explicit(&exec_sibling_ready, memory_order_acquire))
            _exit(91);
        execve(self_path, args, env);
        _exit(100);
    }

    got = wait_bounded(pid, &status, 200);
    if (got == 0) {
        terminate_child(pid);
        return failf("a sibling thread survived successful exec");
    }
    if (got != pid) {
        if (errno != ECHILD)
            terminate_child(pid);
        return failf("wait for multithreaded exec failed");
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 64)
        return failf("multithreaded exec exited with wrong status");
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "self-exec argv and environment", test_argv_and_environment },
    { "successful exec replaces image", test_success_replaces_image },
    { "failed exec leaves image intact", test_failed_exec_keeps_image },
    { "fcntl FD_CLOEXEC", test_fcntl_cloexec },
    { "pipe2 O_CLOEXEC", test_pipe2_cloexec },
    { "exec signal dispositions and mask", test_signal_exec_semantics },
    { "multithreaded exec removes siblings",
      test_multithreaded_exec_removes_siblings },
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
    } else if (got == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        printf("PASS  %s\n", test->name);
        (*passed)++;
    } else if (got == pid && WIFEXITED(status) &&
               WEXITSTATUS(status) == TEST_SKIP) {
        printf("SKIP  %s [unsupported]\n", test->name);
        (*skipped)++;
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
    int skipped = 0;
    int mode;
    size_t i;

    mode = child_mode(argc, argv);
    if (mode >= 0)
        return mode;
    /* If cwd/PATH cannot resolve a bare argv[0], invoke with a pathname. */
    self_path = resolve_self_path(argv[0]);

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_test(&tests[i], &passed, &failed, &skipped);
    printf("SUMMARY exec: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed ? 1 : 0;
}
