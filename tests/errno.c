/*
 * KFS syscall errno test suite.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -o test_errno tests/errno.c
 *
 * Only NULL data pointers and non-dereferencing address arguments are used.
 * In particular, this suite never gives an invalid pathname pointer to KFS.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/futex.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SYS_fcntl64
#define SYS_fcntl64 221
#endif
#ifndef SYS_futex
#define SYS_futex 240
#endif
#ifndef SYS_pipe2
#define SYS_pipe2 331
#endif
#ifndef SYS_wait4
#define SYS_wait4 114
#endif

static int passed;
static int failed;
static int skipped;
static int pipefd[2] = { -1, -1 };

static void pass(const char *name)
{
    printf("PASS %s\n", name);
    passed++;
}

static void fail(const char *name, long result, int got, int expected)
{
    printf("FAIL %s [result=%ld errno=%d, expected -1/%d]\n",
           name, result, got, expected);
    failed++;
}

static void skip(const char *name, const char *why)
{
    printf("SKIP %s [%s]\n", name, why);
    skipped++;
}

static long bad_read_fd(void)
{
    char byte;
    return read(-1, &byte, 1);
}

static long null_read_buffer(void)
{
    const char byte = 'x';

    if (write(pipefd[1], &byte, 1) != 1)
        return -2;
    return syscall(SYS_read, pipefd[0], 0, 1);
}

static long read_from_write_end(void)
{
    char byte;
    return read(pipefd[1], &byte, 1);
}

static long bad_write_fd(void)
{
    const char byte = 'x';
    return write(-1, &byte, 1);
}

static long null_write_buffer(void)
{
    return syscall(SYS_write, pipefd[1], 0, 1);
}

static long write_to_read_end(void)
{
    const char byte = 'x';
    return write(pipefd[0], &byte, 1);
}

static long bad_close(void)
{
    return close(-1);
}

static long double_close(void)
{
    int fd = dup(pipefd[0]);

    if (fd < 0)
        return -2;
    if (close(fd) != 0)
        return -2;
    return close(fd);
}

static long bad_lseek_fd(void)
{
    return lseek(-1, 0, SEEK_SET);
}

static long bad_dup(void)
{
    return dup(-1);
}

static long bad_dup2(void)
{
    return dup2(-1, 40);
}

static long bad_fcntl_fd(void)
{
    return syscall(SYS_fcntl64, -1, F_GETFD, 0);
}

static long bad_fcntl_command(void)
{
    return syscall(SYS_fcntl64, pipefd[0], 0x7fffffff, 0);
}

static long null_pipe2_array(void)
{
    return syscall(SYS_pipe2, 0, 0);
}

static long bad_pipe2_flags(void)
{
    int fds[2];
    return syscall(SYS_pipe2, fds, 0x40000000);
}

static long conflicting_mmap_types(void)
{
    void *p = mmap(NULL, 4096, PROT_READ,
                   MAP_PRIVATE | MAP_SHARED | MAP_ANONYMOUS, -1, 0);

    if (p == MAP_FAILED)
        return -1;
    munmap(p, 4096);
    return 0;
}

static long misaligned_fixed_mmap(void)
{
    void *p = mmap((void *)1, 4096, PROT_READ,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);

    if (p == MAP_FAILED)
        return -1;
    munmap(p, 4096);
    return 0;
}

static long misaligned_munmap(void)
{
    return munmap((void *)1, 4096);
}

static long bad_kill_signal(void)
{
    return kill(getpid(), 999);
}

static long bad_wait_options(void)
{
    int status;
    return syscall(SYS_wait4, -1, &status, 0x01000000, 0);
}

static long no_waitable_children(void)
{
    int status;
    return syscall(SYS_wait4, -1, &status, WNOHANG, 0);
}

static long null_futex_address(void)
{
    return syscall(SYS_futex, 0, FUTEX_WAKE, 1, 0, 0, 0);
}

static long bad_futex_operation(void)
{
    static int word;
    return syscall(SYS_futex, &word, 0x7f, 0, 0, 0, 0);
}

static long zero_futex_bitset(void)
{
    static int word;
    return syscall(SYS_futex, &word, FUTEX_WAIT_BITSET, 1, 0, 0, 0);
}

static long mismatched_futex_value(void)
{
    static int word = 1;
    return syscall(SYS_futex, &word, FUTEX_WAIT, 0, 0, 0, 0);
}

struct errno_case {
    const char *name;
    long (*call)(void);
    int expected_errno;
    int needs_pipe;
};

static const struct errno_case cases[] = {
    { "read rejects a bad fd", bad_read_fd, EBADF, 0 },
    { "read rejects a NULL buffer", null_read_buffer, EFAULT, 1 },
    { "read rejects a write-only fd", read_from_write_end, EBADF, 1 },
    { "write rejects a bad fd", bad_write_fd, EBADF, 0 },
    { "write rejects a NULL buffer", null_write_buffer, EFAULT, 1 },
    { "write rejects a read-only fd", write_to_read_end, EBADF, 1 },
    { "close rejects a negative fd", bad_close, EBADF, 0 },
    { "close rejects an already closed fd", double_close, EBADF, 1 },
    { "lseek rejects a bad fd", bad_lseek_fd, EBADF, 0 },
    { "dup rejects a bad fd", bad_dup, EBADF, 0 },
    { "dup2 rejects a bad source fd", bad_dup2, EBADF, 0 },
    { "fcntl64 rejects a bad fd", bad_fcntl_fd, EBADF, 0 },
    { "fcntl64 rejects an unknown command", bad_fcntl_command, EINVAL, 1 },
    { "pipe2 rejects a NULL result array", null_pipe2_array, EFAULT, 0 },
    { "pipe2 rejects unknown flags", bad_pipe2_flags, EINVAL, 0 },
    { "mmap rejects conflicting sharing types", conflicting_mmap_types, EINVAL, 0 },
    { "MAP_FIXED rejects a misaligned address", misaligned_fixed_mmap, EINVAL, 0 },
    { "munmap rejects a misaligned address", misaligned_munmap, EINVAL, 0 },
    { "kill rejects an invalid signal", bad_kill_signal, EINVAL, 0 },
    { "wait4 rejects unknown option bits", bad_wait_options, EINVAL, 0 },
    // TODO: reparent
    // { "wait4 reports no children", no_waitable_children, ECHILD, 0 },
    { "futex rejects a NULL address", null_futex_address, EFAULT, 0 },
    { "futex rejects an unsupported operation", bad_futex_operation, ENOSYS, 0 },
    { "FUTEX_WAIT_BITSET rejects bitset zero", zero_futex_bitset, EINVAL, 0 },
    { "FUTEX_WAIT detects a value mismatch", mismatched_futex_value, EAGAIN, 0 },
};

static void test_missing_pid(void)
{
    static const pid_t missing = 65535;
    int result;
    int got;

    errno = 0;
    if (access("/proc/65535", F_OK) == 0) {
        skip("kill reports a missing pid", "pid 65535 exists");
        return;
    }
    if (errno != ENOENT && errno != ENOTDIR) {
        skip("kill reports a missing pid", "cannot establish pid absence");
        return;
    }
    errno = 0;
    result = kill(missing, 0);
    got = errno;
    if (result == -1 && got == ESRCH)
        pass("kill reports a missing pid");
    else
        fail("kill reports a missing pid", result, got, ESRCH);
}

int main(void)
{
    int have_pipe;
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    puts("errno suite (Linux/POSIX contracts)");
    have_pipe = pipe(pipefd) == 0;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int got;
        long result;

        if (cases[i].needs_pipe && !have_pipe) {
            skip(cases[i].name, "pipe setup failed");
            continue;
        }
        errno = 0;
        result = cases[i].call();
        got = errno;
        if (result == -1 && got == cases[i].expected_errno)
            pass(cases[i].name);
        else
            fail(cases[i].name, result, got, cases[i].expected_errno);
    }
    test_missing_pid();
    if (have_pipe) {
        close(pipefd[0]);
        close(pipefd[1]);
    }

    printf("SUMMARY pass=%d fail=%d skip=%d\n", passed, failed, skipped);
    return failed != 0;
}
