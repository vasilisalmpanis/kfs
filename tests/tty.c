/*
 * KFS terminal and job-control test suite.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -o test_tty tests/tty.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define CHILD_SKIP 77

enum result { TEST_PASS, TEST_FAIL, TEST_SKIP };

static int passed;
static int failed;
static int skipped;
static int attached_fd = -1;
static int kfs;

static int unavailable_tty_errno(int error)
{
    return error == ENOTTY || error == ENXIO || error == ENODEV ||
           error == ENOENT || error == ENOSYS;
}

static enum result test_non_tty(void)
{
    int fds[2];
    struct termios term;
    int pgid;

    if (pipe(fds) != 0)
        return TEST_SKIP;
    errno = 0;
    if (isatty(fds[0]) != 0 || errno != ENOTTY) {
        close(fds[0]);
        close(fds[1]);
        return TEST_FAIL;
    }
    errno = 0;
    if (tcgetattr(fds[0], &term) != -1 || errno != ENOTTY) {
        close(fds[0]);
        close(fds[1]);
        return TEST_FAIL;
    }
    errno = 0;
    if (ioctl(fds[0], TIOCGPGRP, &pgid) != -1 || errno != ENOTTY) {
        close(fds[0]);
        close(fds[1]);
        return TEST_FAIL;
    }
    close(fds[0]);
    close(fds[1]);
    return TEST_PASS;
}

static enum result test_attached_termios(void)
{
    struct termios first;
    struct termios second;
    size_t i;

    if (attached_fd < 0)
        return TEST_SKIP;
    if (isatty(attached_fd) != 1)
        return TEST_FAIL;
    memset(&first, 0, sizeof(first));
    memset(&second, 0, sizeof(second));
    if (tcgetattr(attached_fd, &first) != 0 ||
        tcgetattr(attached_fd, &second) != 0)
        return TEST_FAIL;
    if (first.c_iflag != second.c_iflag || first.c_oflag != second.c_oflag ||
        first.c_cflag != second.c_cflag || first.c_lflag != second.c_lflag ||
        cfgetispeed(&first) != cfgetispeed(&second) ||
        cfgetospeed(&first) != cfgetospeed(&second))
        return TEST_FAIL;
    for (i = 0; i < NCCS; i++) {
        if (first.c_cc[i] != second.c_cc[i])
            return TEST_FAIL;
    }
    return TEST_PASS;
}

static enum result test_window_size(void)
{
    struct winsize size;

    if (attached_fd < 0)
        return TEST_SKIP;
    memset(&size, 0, sizeof(size));
    if (ioctl(attached_fd, TIOCGWINSZ, &size) == 0)
        return TEST_PASS;
    return unavailable_tty_errno(errno) ? TEST_SKIP : TEST_FAIL;
}

static enum result test_foreground_group(void)
{
    pid_t foreground;

    if (attached_fd < 0)
        return TEST_SKIP;
    foreground = tcgetpgrp(attached_fd);
    if (foreground > 0)
        return TEST_PASS;
    return unavailable_tty_errno(errno) ? TEST_SKIP : TEST_FAIL;
}

static int child_new_session_without_tty(void)
{
    int fd;

    if (setsid() != getpid())
        return 1;
    errno = 0;
    fd = open("/dev/tty", O_RDWR | O_NOCTTY);
    if (fd >= 0) {
        close(fd);
        return 2;
    }
    if (errno == ENXIO)
        return 0;
    if (errno == ENOENT)
        return kfs ? 0 : CHILD_SKIP;
    return 3;
}

static int child_inherited_job_control(void)
{
    pid_t foreground;
    pid_t session;

    if (attached_fd < 0)
        return CHILD_SKIP;
    if (getpgrp() <= 0 || getsid(0) <= 0)
        return 1;
    foreground = tcgetpgrp(attached_fd);
    if (foreground <= 0)
        return unavailable_tty_errno(errno) ? CHILD_SKIP : 2;
    if (signal(SIGTTOU, SIG_IGN) == SIG_ERR)
        return 3;
    if (tcsetpgrp(attached_fd, foreground) != 0)
        return unavailable_tty_errno(errno) ? CHILD_SKIP : 4;
#ifdef TIOCGSID
    if (ioctl(attached_fd, TIOCGSID, &session) == 0) {
        if (session <= 0)
            return 5;
    } else if (errno != ENOTTY && errno != EINVAL && errno != ENOSYS) {
        return 5;
    }
#else
    (void)session;
#endif
    return tcgetpgrp(attached_fd) == foreground ? 0 : 6;
}

static int allocate_pty(char *path, size_t size, int *master)
{
    *master = posix_openpt(O_RDWR | O_NOCTTY);
    if (*master >= 0 && grantpt(*master) == 0 && unlockpt(*master) == 0 &&
        ptsname_r(*master, path, size) == 0)
        return 0;
    if (*master >= 0) {
        close(*master);
        *master = -1;
    }
    return -1;
}

static int child_controlling_tty(void)
{
    char path[128];
    int master = -1;
    int fd;
    pid_t sid;
    pid_t foreground;

    if (allocate_pty(path, sizeof(path), &master) != 0)
        return CHILD_SKIP;
    if (setsid() != getpid()) {
        if (master >= 0)
            close(master);
        return 1;
    }
    fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        if (master >= 0)
            close(master);
        return errno == ENOENT || errno == ENODEV || errno == EACCES ?
               CHILD_SKIP : 2;
    }
    if (ioctl(fd, TIOCSCTTY, 0) != 0) {
        int result = errno == ENOTTY || errno == ENOSYS ? CHILD_SKIP : 3;
        close(fd);
        if (master >= 0)
            close(master);
        return result;
    }
    sid = getsid(0);
    foreground = tcgetpgrp(fd);
    if (sid != getpid() || foreground <= 0) {
        close(fd);
        if (master >= 0)
            close(master);
        return 4;
    }
#ifdef TIOCGSID
    {
        pid_t tty_sid = -1;
        if (ioctl(fd, TIOCGSID, &tty_sid) == 0) {
            if (tty_sid != sid) {
                close(fd);
                if (master >= 0)
                    close(master);
                return 5;
            }
        } else if (errno != ENOTTY && errno != EINVAL && errno != ENOSYS) {
            close(fd);
            if (master >= 0)
                close(master);
            return 5;
        }
    }
#endif
    if (signal(SIGTTOU, SIG_IGN) == SIG_ERR) {
        close(fd);
        if (master >= 0)
            close(master);
        return 6;
    }
    if (tcsetpgrp(fd, getpgrp()) != 0 || tcgetpgrp(fd) != getpgrp()) {
        close(fd);
        if (master >= 0)
            close(master);
        return 7;
    }
    if (signal(SIGHUP, SIG_IGN) == SIG_ERR) {
        close(fd);
        if (master >= 0)
            close(master);
        return 8;
    }
    close(fd);
    if (master >= 0)
        close(master);
    return 0;
}

static enum result run_child(int (*child)(void))
{
    pid_t pid = fork();
    int status = 0;
    unsigned tick;

    if (pid < 0)
        return TEST_SKIP;
    if (pid == 0)
        _exit(child());
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

struct test_case {
    const char *name;
    enum result (*run)(void);
};

static enum result isolated_no_tty(void)
{
    return run_child(child_new_session_without_tty);
}

static enum result isolated_job_control(void)
{
    return run_child(child_inherited_job_control);
}

static enum result isolated_controlling_tty(void)
{
    return run_child(child_controlling_tty);
}

static const struct test_case tests[] = {
    { "ioctl and tcgetattr reject a non-TTY", test_non_tty },
    { "isatty and tcgetattr on attached terminal", test_attached_termios },
    { "terminal window size", test_window_size },
    { "foreground process group", test_foreground_group },
    { "setsid detaches controlling terminal", isolated_no_tty },
    { "inherited session and foreground pgid", isolated_job_control },
    { "acquire controlling terminal as session leader", isolated_controlling_tty },
};

int main(void)
{
    struct utsname uts;
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    kfs = uname(&uts) == 0 && strcmp(uts.sysname, "kfs") == 0;
    for (i = 0; i < 3; i++) {
        if (isatty((int)i)) {
            attached_fd = (int)i;
            break;
        }
    }
    printf("tty suite (%s)\n", attached_fd >= 0 ? "terminal attached" : "no terminal");
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
            printf("SKIP %s [no suitable terminal or unsupported ioctl]\n", tests[i].name);
            skipped++;
        } else {
            if (saved_errno != 0)
                printf("FAIL %s [errno=%d: %s]\n",
                       tests[i].name, saved_errno, strerror(saved_errno));
            else
                printf("FAIL %s [terminal state mismatch]\n", tests[i].name);
            failed++;
        }
    }
    printf("SUMMARY pass=%d fail=%d skip=%d\n", passed, failed, skipped);
    return failed != 0;
}
