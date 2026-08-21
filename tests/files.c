/*
 * Regular-file and directory conformance tests.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_files tests/files.c
 */
#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_TIMEOUT_TICKS 500
#define CHILD_WAIT_TICKS 300
#define POST_KILL_TICKS 100
#define RECORD_SIZE 64
#define PWRITE_WORKERS 4

enum { TEST_PASS = 0, TEST_FAIL = 1, TEST_SKIP = 77 };

static int passed;
static int failed;
static int skipped;

static int failf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stdout);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    return TEST_FAIL;
}

static int skipf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stdout);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    return TEST_SKIP;
}

static void temp_name(char *buffer, size_t size, const char *tag)
{
    snprintf(buffer, size, "kfs_files_%ld_%s", (long)getpid(), tag);
}

static int write_exact(int fd, const void *buffer, size_t size)
{
    const unsigned char *p = buffer;

    while (size != 0) {
        ssize_t n = write(fd, p, size);

        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        p += n;
        size -= (size_t)n;
    }
    return 0;
}

static int read_exact(int fd, void *buffer, size_t size)
{
    unsigned char *p = buffer;

    while (size != 0) {
        ssize_t n = read(fd, p, size);

        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        p += n;
        size -= (size_t)n;
    }
    return 0;
}

static void cpu_relax(void)
{
#if defined(__i386__) || defined(__x86_64__)
    __asm__ volatile("pause" ::: "memory");
#else
    atomic_signal_fence(memory_order_seq_cst);
#endif
}

static pid_t waitpid_bounded(pid_t pid, int *status, unsigned ticks)
{
    unsigned tick;

    for (tick = 0; tick < ticks; tick++) {
        pid_t result = waitpid(pid, status, WNOHANG);

        if (result == pid || (result < 0 && errno != EINTR))
            return result;
        usleep(10000);
    }
    return 0;
}

static int wait_ok(pid_t pid)
{
    int status = 0;
    pid_t result = waitpid_bounded(pid, &status, CHILD_WAIT_TICKS);

    if (result == 0) {
        kill(pid, SIGKILL);
        (void)waitpid_bounded(pid, &status, POST_KILL_TICKS);
        return 0;
    }
    return result == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int test_create_read_write_lseek(void)
{
    static const char initial[] = "abcdef";
    char path[96], buffer[sizeof(initial)];
    int fd;

    temp_name(path, sizeof(path), "basic");
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0)
        return failf("open(O_CREAT|O_EXCL): %s", strerror(errno));
    if (write_exact(fd, initial, sizeof(initial)) != 0)
        return failf("write: %s", strerror(errno));
    if (lseek(fd, 0, SEEK_SET) != 0 ||
        read_exact(fd, buffer, sizeof(buffer)) != 0 ||
        memcmp(buffer, initial, sizeof(buffer)) != 0)
        return failf("read after SEEK_SET was incorrect");
    if (lseek(fd, -3, SEEK_END) != (off_t)(sizeof(initial) - 3) ||
        write_exact(fd, "XY", 2) != 0)
        return failf("SEEK_END/overwrite failed: %s", strerror(errno));
    if (lseek(fd, -2, SEEK_CUR) != (off_t)(sizeof(initial) - 3) ||
        read_exact(fd, buffer, 2) != 0 || memcmp(buffer, "XY", 2) != 0)
        return failf("SEEK_CUR did not track the write offset");
    close(fd);
    if (unlink(path) != 0)
        return failf("cleanup unlink: %s", strerror(errno));
    return TEST_PASS;
}

static int test_stat_fstat_consistency(void)
{
    char path[96];
    struct stat by_path, by_fd;
    int fd;

    temp_name(path, sizeof(path), "stat");
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0640);
    if (fd < 0 || write_exact(fd, "stat-data", 9) != 0)
        return failf("file setup: %s", strerror(errno));
    if (stat(path, &by_path) != 0 || fstat(fd, &by_fd) != 0)
        return failf("stat/fstat: %s", strerror(errno));
    if (by_path.st_dev != by_fd.st_dev || by_path.st_ino != by_fd.st_ino ||
        by_path.st_mode != by_fd.st_mode || by_path.st_nlink != by_fd.st_nlink ||
        by_path.st_size != by_fd.st_size || by_path.st_size != 9 ||
        !S_ISREG(by_path.st_mode))
        return failf("stat and fstat metadata disagreed");
    close(fd);
    unlink(path);
    return TEST_PASS;
}

static int test_unlink_open_lifetime(void)
{
    char path[96], buffer[8];
    struct stat st;
    int fd;

    temp_name(path, sizeof(path), "unlinked");
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0 || write_exact(fd, "persist", 7) != 0)
        return failf("file setup: %s", strerror(errno));
    if (unlink(path) != 0)
        return failf("unlink open file: %s", strerror(errno));
    errno = 0;
    if (stat(path, &st) != -1 || errno != ENOENT)
        return failf("unlinked pathname still resolved");
    memset(buffer, 0, sizeof(buffer));
    if (lseek(fd, 0, SEEK_SET) != 0 || read_exact(fd, buffer, 7) != 0 ||
        memcmp(buffer, "persist", 7) != 0)
        return failf("open descriptor did not survive unlink");
    close(fd);
    errno = 0;
    fd = open(path, O_RDONLY);
    if (fd != -1 || errno != ENOENT) {
        if (fd >= 0)
            close(fd);
        return failf("file reappeared after final close");
    }
    return TEST_PASS;
}

static int test_shared_offset_after_fork(void)
{
    char path[96], buffer[3] = {0};
    pid_t child;
    int fd;

    temp_name(path, sizeof(path), "fork_offset");
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0 || write_exact(fd, "abcdef", 6) != 0 ||
        lseek(fd, 0, SEEK_SET) != 0)
        return failf("file setup: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        char first[2];
        _exit(read_exact(fd, first, sizeof(first)) == 0 &&
              memcmp(first, "ab", 2) == 0 ? 0 : 2);
    }
    if (!wait_ok(child))
        return failf("child could not consume first two bytes");
    if (read_exact(fd, buffer, 2) != 0 || memcmp(buffer, "cd", 2) != 0)
        return failf("fork did not share the open-file offset");
    close(fd);
    unlink(path);
    return TEST_PASS;
}

static int test_independent_open_offsets(void)
{
    char path[96], a[3] = {0}, b[3] = {0};
    int first, second;

    temp_name(path, sizeof(path), "independent");
    unlink(path);
    first = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (first < 0 || write_exact(first, "abcdef", 6) != 0)
        return failf("file setup: %s", strerror(errno));
    second = open(path, O_RDONLY);
    if (second < 0 || lseek(first, 0, SEEK_SET) != 0)
        return failf("second open: %s", strerror(errno));
    if (read_exact(first, a, 2) != 0 || read_exact(second, b, 2) != 0 ||
        memcmp(a, "ab", 2) != 0 || memcmp(b, "ab", 2) != 0)
        return failf("independent opens unexpectedly shared offsets");
    if (lseek(first, 0, SEEK_CUR) != 2 || lseek(second, 0, SEEK_CUR) != 2)
        return failf("independent offsets were not advanced correctly");
    close(second);
    close(first);
    unlink(path);
    return TEST_PASS;
}

static int test_append(void)
{
    char path[96], buffer[3] = {0};
    int fd;

    temp_name(path, sizeof(path), "append");
    unlink(path);
    fd = open(path, O_CREAT | O_EXCL | O_RDWR | O_APPEND, 0600);
    if (fd < 0) {
        if (errno == ENOSYS || errno == EOPNOTSUPP)
            return skipf("O_APPEND is unsupported");
        return failf("open O_APPEND: %s", strerror(errno));
    }
    if (write_exact(fd, "A", 1) != 0 || lseek(fd, 0, SEEK_SET) != 0 ||
        write_exact(fd, "B", 1) != 0 || lseek(fd, 0, SEEK_SET) != 0 ||
        read_exact(fd, buffer, 2) != 0 || memcmp(buffer, "AB", 2) != 0)
        return failf("O_APPEND did not force writes to end of file");
    close(fd);
    unlink(path);
    return TEST_PASS;
}

struct pwrite_arg {
    int fd;
    unsigned index;
};

static atomic_int pwrite_start;
static atomic_int pwrite_errors;

static void *pwrite_worker(void *opaque)
{
    struct pwrite_arg *arg = opaque;
    unsigned char data[RECORD_SIZE];
    unsigned iteration;

    memset(data, 'A' + (int)arg->index, sizeof(data));
    while (!atomic_load_explicit(&pwrite_start, memory_order_acquire))
        cpu_relax();
    for (iteration = 0; iteration < 100; iteration++) {
        off_t offset = (off_t)(arg->index + 1) * RECORD_SIZE;
        if (pwrite(arg->fd, data, sizeof(data), offset) != (ssize_t)sizeof(data)) {
            atomic_fetch_add_explicit(&pwrite_errors, 1, memory_order_relaxed);
            break;
        }
    }
    return NULL;
}

static int test_concurrent_pwrite_pread(void)
{
    char path[96];
    unsigned char initial[(PWRITE_WORKERS + 1) * RECORD_SIZE];
    unsigned char buffer[RECORD_SIZE];
    struct pwrite_arg args[PWRITE_WORKERS];
    pthread_t threads[PWRITE_WORKERS];
    unsigned created = 0;
    unsigned i;
    int fd;
    ssize_t result;

    temp_name(path, sizeof(path), "pwrite");
    unlink(path);
    memset(initial, 'H', sizeof(initial));
    fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0 || write_exact(fd, initial, sizeof(initial)) != 0)
        return failf("file setup: %s", strerror(errno));
    if (lseek(fd, 7, SEEK_SET) != 7)
        return failf("initial seek failed");

    errno = 0;
    result = pwrite(fd, initial + RECORD_SIZE, RECORD_SIZE, RECORD_SIZE);
    if (result < 0 && (errno == ENOSYS || errno == EOPNOTSUPP ||
                       errno == EINVAL)) {
        close(fd);
        unlink(path);
        return skipf("pwrite is unsupported");
    }
    if (result != RECORD_SIZE)
        return failf("pwrite probe: %s", strerror(errno));
    errno = 0;
    result = pread(fd, buffer, sizeof(buffer), 0);
    if (result < 0 && (errno == ENOSYS || errno == EOPNOTSUPP)) {
        close(fd);
        unlink(path);
        return skipf("pread is unsupported");
    }
    if (result != RECORD_SIZE)
        return failf("pread probe: %s", strerror(errno));

    atomic_store(&pwrite_start, 0);
    atomic_store(&pwrite_errors, 0);
    for (i = 0; i < PWRITE_WORKERS; i++) {
        args[i].fd = fd;
        args[i].index = i;
        if (pthread_create(&threads[i], NULL, pwrite_worker, &args[i]) != 0)
            break;
        created++;
    }
    if (created != PWRITE_WORKERS)
        return failf("created only %u pwrite workers", created);
    atomic_store_explicit(&pwrite_start, 1, memory_order_release);
    for (i = 0; i < 200; i++) {
        if (pread(fd, buffer, sizeof(buffer), 0) != RECORD_SIZE)
            return failf("concurrent pread failed");
        if (buffer[0] != 'H' || buffer[RECORD_SIZE - 1] != 'H')
            return failf("concurrent read of stable region was corrupted");
    }
    for (i = 0; i < PWRITE_WORKERS; i++)
        pthread_join(threads[i], NULL);
    if (atomic_load(&pwrite_errors) != 0 || lseek(fd, 0, SEEK_CUR) != 7)
        return failf("positioned I/O failed or changed shared offset");
    for (i = 0; i < PWRITE_WORKERS; i++) {
        memset(buffer, 0, sizeof(buffer));
        if (pread(fd, buffer, sizeof(buffer), (off_t)(i + 1) * RECORD_SIZE) !=
                RECORD_SIZE ||
            buffer[0] != (unsigned char)('A' + i) ||
            buffer[RECORD_SIZE - 1] != (unsigned char)('A' + i))
            return failf("pwrite worker %u region was incorrect", i);
    }
    close(fd);
    unlink(path);
    return TEST_PASS;
}

static int test_directory_operations(void)
{
    char directory[96], first_path[128], second_path[128];
    int dfd = -1, fd = -1;
    DIR *stream = NULL;
    struct dirent *entry;
    int saw_first = 0, saw_second = 0;

    temp_name(directory, sizeof(directory), "dir");
    snprintf(first_path, sizeof(first_path), "%s/first", directory);
    snprintf(second_path, sizeof(second_path), "%s/second", directory);
    unlink(first_path);
    unlink(second_path);
    rmdir(directory);
    if (mkdir(directory, 0700) != 0)
        return failf("mkdir: %s", strerror(errno));
    dfd = open(directory, O_RDONLY | O_DIRECTORY);
    if (dfd < 0)
        return failf("open directory: %s", strerror(errno));
    fd = openat(dfd, "first", O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0 || write_exact(fd, "1", 1) != 0)
        return failf("openat first: %s", strerror(errno));
    close(fd);
    fd = openat(dfd, "second", O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0 || write_exact(fd, "2", 1) != 0)
        return failf("openat second: %s", strerror(errno));
    close(fd);

    stream = opendir(directory);
    if (stream == NULL)
        return failf("opendir: %s", strerror(errno));
    errno = 0;
    while ((entry = readdir(stream)) != NULL) {
        if (strcmp(entry->d_name, "first") == 0)
            saw_first = 1;
        if (strcmp(entry->d_name, "second") == 0)
            saw_second = 1;
    }
    if (errno != 0 || !saw_first || !saw_second)
        return failf("readdir did not enumerate both temporary files");
    closedir(stream);
    close(dfd);
    if (unlink(first_path) != 0 || unlink(second_path) != 0 ||
        rmdir(directory) != 0)
        return failf("directory cleanup: %s", strerror(errno));
    return TEST_PASS;
}

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "create/open/read/write/lseek", test_create_read_write_lseek },
    { "stat and fstat consistency", test_stat_fstat_consistency },
    { "unlink-open lifetime", test_unlink_open_lifetime },
    { "shared offset after fork", test_shared_offset_after_fork },
    { "independent open offsets", test_independent_open_offsets },
    { "append semantics", test_append },
    { "concurrent pwrite/pread", test_concurrent_pwrite_pread },
    { "directory operations", test_directory_operations },
};

static void run_isolated(const struct test_case *test)
{
    pid_t child;
    pid_t result = 0;
    int status = 0;
    int code;
    unsigned tick;

    child = fork();
    if (child < 0) {
        printf("FAIL %s (fork: %s)\n", test->name, strerror(errno));
        failed++;
        return;
    }
    if (child == 0) {
        (void)setpgid(0, 0);
        _exit(test->run());
    }
    (void)setpgid(child, child);
    for (tick = 0; tick < TEST_TIMEOUT_TICKS && result == 0; tick++) {
        result = waitpid(child, &status, WNOHANG);
        if (result < 0 && errno == EINTR)
            result = 0;
        if (result == 0)
            usleep(10000);
    }
    if (result == 0) {
        pid_t reaped;

        kill(-child, SIGKILL);
        kill(child, SIGKILL);
        reaped = waitpid_bounded(child, &status, POST_KILL_TICKS);
        printf("FAIL %s (timeout%s)\n", test->name,
               reaped == child ? "" : "; child not reaped");
        failed++;
        return;
    }
    if (result != child) {
        printf("FAIL %s (waitpid: %s)\n", test->name, strerror(errno));
        failed++;
        return;
    }
    code = WIFEXITED(status) ? WEXITSTATUS(status) : TEST_FAIL;
    if (code == TEST_PASS) {
        printf("PASS %s\n", test->name);
        passed++;
    } else if (code == TEST_SKIP) {
        printf("SKIP %s\n", test->name);
        skipped++;
    } else {
        printf("FAIL %s (%s)\n", test->name,
               WIFSIGNALED(status) ? "signal" : "test error");
        failed++;
    }
}

int main(void)
{
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_isolated(&tests[i]);
    printf("files: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed != 0;
}
