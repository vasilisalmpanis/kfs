/*
 * KFS credentials and filesystem-permission test suite.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -o test_permissions tests/permissions.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define CHILD_SKIP 77

enum result { TEST_PASS, TEST_FAIL, TEST_SKIP };

static int passed;
static int failed;
static int skipped;
static char directory[128];
static char normal_path[160];
static char denied_path[160];
static char masked_path[160];
static char owned_path[160];
static char chown_denied_path[160];

static int create_file(const char *path, mode_t mode)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, mode);

    if (fd < 0)
        return -1;
    if (write(fd, "x", 1) != 1) {
        int saved = errno;

        close(fd);
        unlink(path);
        errno = saved;
        return -1;
    }
    return fd;
}

static enum result test_identity_getters(void)
{
    gid_t groups[64];
    uid_t uid = getuid();
    uid_t euid = geteuid();
    gid_t gid = getgid();
    gid_t egid = getegid();
    int count = getgroups(0, NULL);

    if (uid != getuid() || euid != geteuid() ||
        gid != getgid() || egid != getegid())
        return TEST_FAIL;
    if (count < 0)
        return TEST_FAIL;
    if (count > (int)ARRAY_SIZE(groups))
        return TEST_SKIP;
    if (getgroups(count, count == 0 ? NULL : groups) != count)
        return TEST_FAIL;
    return TEST_PASS;
}

static enum result test_chmod_and_access(void)
{
    struct stat status;
    int fd = create_file(normal_path, 0600);

    if (fd < 0)
        return TEST_FAIL;
    close(fd);
    if (chmod(normal_path, 0400) != 0 || stat(normal_path, &status) != 0)
        return TEST_FAIL;
    if ((status.st_mode & 0777) != 0400)
        return TEST_FAIL;
    if (access(normal_path, F_OK | R_OK) != 0)
        return TEST_FAIL;
    fd = open(normal_path, O_RDONLY);
    if (fd < 0)
        return TEST_FAIL;
    close(fd);
    return TEST_PASS;
}

static enum result test_denied_access(void)
{
    int access_result;
    int access_errno;
    int fd;
    int open_errno;

    errno = 0;
    access_result = access(denied_path, R_OK);
    access_errno = errno;
    errno = 0;
    fd = open(denied_path, O_RDONLY);
    open_errno = errno;
    if (fd >= 0) {
        close(fd);
        if (access_result == 0 && geteuid() == 0)
            return TEST_SKIP;
        return TEST_FAIL;
    }
    return access_result == -1 && access_errno == EACCES &&
           open_errno == EACCES ? TEST_PASS : TEST_FAIL;
}

static int child_dropped_access(void)
{
    int fd;

    if (geteuid() != 0)
        return CHILD_SKIP;
    (void)setgroups(0, NULL);
    if (setgid(65534) != 0 || setuid(65534) != 0)
        return CHILD_SKIP;
    if (geteuid() == 0 || getegid() == 0)
        return 1;
    if (access(denied_path, F_OK) != 0)
        return 2;
    errno = 0;
    if (access(denied_path, R_OK) != -1 || errno != EACCES)
        return 3;
    errno = 0;
    fd = open(denied_path, O_RDONLY);
    if (fd >= 0) {
        close(fd);
        return 4;
    }
    return errno == EACCES ? 0 : 5;
}

static enum result test_umask(void)
{
    struct stat status;
    mode_t old_mask;
    int fd;

    old_mask = umask(0077);
    fd = create_file(masked_path, 0666);
    umask(old_mask);
    if (fd < 0)
        return TEST_FAIL;
    close(fd);
    if (stat(masked_path, &status) != 0)
        return TEST_FAIL;
    return (status.st_mode & 0777) == 0600 ? TEST_PASS : TEST_FAIL;
}

static enum result test_ownership_calls(void)
{
    struct stat status;
    int fd = create_file(owned_path, 0600);

    if (fd < 0)
        return TEST_FAIL;
    if (fstat(fd, &status) != 0) {
        close(fd);
        return TEST_FAIL;
    }
    errno = 0;
    if (fchown(fd, status.st_uid, status.st_gid) != 0) {
        int saved = errno;
        close(fd);
        if (saved == ENOSYS)
            return TEST_SKIP;
        return TEST_FAIL;
    }
    close(fd);
    errno = 0;
    if (chown(owned_path, status.st_uid, status.st_gid) != 0) {
        if (errno == ENOSYS)
            return TEST_SKIP;
        return TEST_FAIL;
    }
    if (stat(owned_path, &status) != 0)
        return TEST_FAIL;
    return status.st_uid == geteuid() && status.st_gid == getegid() ?
           TEST_PASS : TEST_FAIL;
}

static int child_arbitrary_chown_denied(void)
{
    uid_t target;
    int result;
    int saved;

    if (geteuid() == 0) {
        (void)setgroups(0, NULL);
        if (setgid(65534) != 0 || setuid(65534) != 0)
            return CHILD_SKIP;
    }
    target = geteuid() == 65534 ? 65533 : geteuid() + 1;
    errno = 0;
    result = chown(chown_denied_path, target, getegid());
    saved = errno;
    if (result == -1 && saved == ENOSYS)
        return CHILD_SKIP;
    return result == -1 && saved == EPERM ? 0 : 1;
}

static int wait_bounded(pid_t pid, int *status)
{
    unsigned tick;

    for (tick = 0; tick < 50; tick++) {
        pid_t result = waitpid(pid, status, WNOHANG);

        if (result == pid)
            return 0;
        if (result < 0 && errno != EINTR)
            break;
        usleep(100000);
    }
    kill(pid, SIGKILL);
    for (tick = 0; tick < 20; tick++) {
        pid_t result = waitpid(pid, status, WNOHANG);

        if (result == pid)
            break;
        if (result < 0 && errno != EINTR)
            break;
        usleep(100000);
    }
    return -1;
}

static enum result test_same_uid_kill(void)
{
    int control[2];
    pid_t pid;
    int status = 0;
    char byte = 'x';
    int result;

    if (pipe(control) != 0)
        return TEST_SKIP;
    pid = fork();
    if (pid == 0) {
        close(control[1]);
        _exit(read(control[0], &byte, 1) == 1 ? 0 : 1);
    }
    close(control[0]);
    if (pid < 0) {
        close(control[1]);
        return TEST_SKIP;
    }
    result = kill(pid, 0);
    (void)write(control[1], &byte, 1);
    close(control[1]);
    if (wait_bounded(pid, &status) != 0)
        return TEST_FAIL;
    if (result != 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return TEST_FAIL;
    return TEST_PASS;
}

static int child_denied_kill(void)
{
    if (geteuid() != 0)
        return CHILD_SKIP;
    (void)setgroups(0, NULL);
    if (setgid(65534) != 0 || setuid(65534) != 0)
        return CHILD_SKIP;
    errno = 0;
    return kill(getppid(), 0) == -1 && errno == EPERM ? 0 : 1;
}

static enum result run_child(int (*child)(void))
{
    pid_t pid = fork();
    int status = 0;

    if (pid < 0)
        return TEST_SKIP;
    if (pid == 0)
        _exit(child());
    if (wait_bounded(pid, &status) != 0 || !WIFEXITED(status))
        return TEST_FAIL;
    if (WEXITSTATUS(status) == CHILD_SKIP)
        return TEST_SKIP;
    return WEXITSTATUS(status) == 0 ? TEST_PASS : TEST_FAIL;
}

static enum result isolated_dropped_access(void)
{
    return run_child(child_dropped_access);
}

static enum result isolated_denied_kill(void)
{
    return run_child(child_denied_kill);
}

static enum result isolated_arbitrary_chown(void)
{
    return run_child(child_arbitrary_chown_denied);
}

struct test_case {
    const char *name;
    enum result (*run)(void);
};

static const struct test_case tests[] = {
    { "uid, gid, and supplementary group getters", test_identity_getters },
    { "chmod and allowed access/open", test_chmod_and_access },
    { "denied access/open for non-root owner", test_denied_access },
    { "denied access after isolated root drop", isolated_dropped_access },
    { "umask affects newly created file", test_umask },
    { "implemented ownership calls", test_ownership_calls },
    { "non-root arbitrary chown is denied", isolated_arbitrary_chown },
    { "kill signal zero for same uid", test_same_uid_kill },
    { "kill permission after isolated root drop", isolated_denied_kill },
};

static int setup_directory(void)
{
    unsigned attempt;

    for (attempt = 0; attempt < 10; attempt++) {
        snprintf(directory, sizeof(directory), "/tmp/kfs-permissions-%ld-%u",
                 (long)getpid(), attempt);
        if (mkdir(directory, 0700) == 0)
            break;
        if (errno != EEXIST)
            return -1;
    }
    if (attempt == 10)
        return -1;
    if (chmod(directory, 0755) != 0)
        return -1;
    snprintf(normal_path, sizeof(normal_path), "%s/normal", directory);
    snprintf(denied_path, sizeof(denied_path), "%s/denied", directory);
    snprintf(masked_path, sizeof(masked_path), "%s/masked", directory);
    snprintf(owned_path, sizeof(owned_path), "%s/owned", directory);
    snprintf(chown_denied_path, sizeof(chown_denied_path), "%s/chown-denied",
             directory);

    {
        int fd = create_file(denied_path, 0600);
        if (fd < 0)
            return -1;
        close(fd);
        if (chmod(denied_path, 0000) != 0)
            return -1;
        fd = create_file(chown_denied_path, 0600);
        if (fd < 0)
            return -1;
        close(fd);
    }
    return 0;
}

static int cleanup_directory(void)
{
    int result = 0;

    chmod(normal_path, 0600);
    chmod(denied_path, 0600);
    chmod(masked_path, 0600);
    chmod(owned_path, 0600);
    chmod(chown_denied_path, 0600);
    if (unlink(normal_path) != 0 && errno != ENOENT)
        result = -1;
    if (unlink(denied_path) != 0 && errno != ENOENT)
        result = -1;
    if (unlink(masked_path) != 0 && errno != ENOENT)
        result = -1;
    if (unlink(owned_path) != 0 && errno != ENOENT)
        result = -1;
    if (unlink(chown_denied_path) != 0 && errno != ENOENT)
        result = -1;
    if (directory[0] != '\0' && rmdir(directory) != 0 && errno != ENOENT)
        result = -1;
    return result;
}

int main(void)
{
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    puts("permissions suite");
    if (setup_directory() != 0) {
        int saved = errno;

        cleanup_directory();
        printf("FAIL temporary directory setup [errno=%d: %s]\n",
               saved, strerror(saved));
        printf("SUMMARY pass=0 fail=1 skip=0\n");
        return 1;
    }
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
            printf("SKIP %s [root bypass, privilege, or syscall unavailable]\n",
                   tests[i].name);
            skipped++;
        } else {
            if (saved_errno != 0)
                printf("FAIL %s [errno=%d: %s]\n",
                       tests[i].name, saved_errno, strerror(saved_errno));
            else
                printf("FAIL %s [permission result mismatch]\n", tests[i].name);
            failed++;
        }
    }
    if (cleanup_directory() != 0) {
        printf("FAIL temporary directory cleanup\n");
        failed++;
    }
    printf("SUMMARY pass=%d fail=%d skip=%d\n", passed, failed, skipped);
    return failed != 0;
}
