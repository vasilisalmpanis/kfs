/*
 * Pipe conformance tests.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_pipe tests/pipe.c
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_TIMEOUT_TICKS 500
#define CHILD_WAIT_TICKS 300
#define POST_KILL_TICKS 100
#define BLOCK_CONFIRM_TICKS 10
#define MAX_DISCOVERED_CAPACITY (1024u * 1024u)

static int passed;
static int failed;

static int failf(const char *fmt, ...)
{
    va_list ap;

    fputs("    ", stdout);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    return 1;
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

/*
 * The ready byte is emitted immediately before the potentially blocking call.
 * Without kernel wait-state introspection this cannot prove the child is
 * asleep in that call; it proves only that the child did not complete during
 * this bounded observation window before the parent supplies the wake event.
 */
static int child_remains_alive(pid_t pid)
{
    unsigned tick;

    for (tick = 0; tick < BLOCK_CONFIRM_TICKS; tick++) {
        pid_t result;

        usleep(10000);
        result = waitpid(pid, NULL, WNOHANG);
        if (result == 0)
            continue;
        if (result < 0 && errno == EINTR)
            continue;
        return 0;
    }
    return 1;
}

static int set_nonblock(int fd, int enabled)
{
    int flags = fcntl(fd, F_GETFL);

    if (flags < 0)
        return -1;
    if (enabled)
        flags |= O_NONBLOCK;
    else
        flags &= ~O_NONBLOCK;
    return fcntl(fd, F_SETFL, flags);
}

static ssize_t fill_nonblocking(int fd)
{
    unsigned char data[256];
    size_t total = 0;

    memset(data, 0x5a, sizeof(data));
    if (set_nonblock(fd, 1) != 0)
        return -1;
    while (total < MAX_DISCOVERED_CAPACITY) {
        ssize_t n = write(fd, data, sizeof(data));

        if (n > 0) {
            total += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return (ssize_t)total;
        return -1;
    }
    errno = EOVERFLOW;
    return -1;
}

static int test_direction_and_transfer(void)
{
    static const char message[] = "one-way pipe";
    char buffer[sizeof(message)];
    int p[2];
    char byte;

    if (pipe(p) != 0)
        return failf("pipe: %s", strerror(errno));
    if (write_exact(p[1], message, sizeof(message)) != 0 ||
        read_exact(p[0], buffer, sizeof(buffer)) != 0 ||
        memcmp(buffer, message, sizeof(message)) != 0)
        return failf("basic transfer was corrupted");

    errno = 0;
    if (read(p[1], &byte, 1) != -1 || errno != EBADF)
        return failf("read from write end did not fail with EBADF");
    errno = 0;
    if (write(p[0], &byte, 1) != -1 || errno != EBADF)
        return failf("write to read end did not fail with EBADF");
    close(p[0]);
    close(p[1]);
    return 0;
}

static int test_blocked_reader_wakes(void)
{
    int data[2], ready[2];
    pid_t child;
    char byte;

    if (pipe(data) != 0 || pipe(ready) != 0)
        return failf("pipe setup: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        close(data[1]);
        close(ready[0]);
        if (write_exact(ready[1], "R", 1) != 0)
            _exit(2);
        if (read(data[0], &byte, 1) != 1 || byte != 'W')
            _exit(3);
        _exit(0);
    }

    close(data[0]);
    close(ready[1]);
    if (read_exact(ready[0], &byte, 1) != 0)
        return failf("reader pre-read handshake failed");
    if (!child_remains_alive(child))
        return failf("empty pipe read completed before data was written");
    if (write_exact(data[1], "W", 1) != 0)
        return failf("wake write: %s", strerror(errno));
    close(data[1]);
    close(ready[0]);
    if (!wait_ok(child))
        return failf("blocked reader did not receive the byte");
    return 0;
}

static int test_nonblocking_eagain(void)
{
    int p[2];
    char byte;
    ssize_t capacity;

    if (pipe(p) != 0)
        return failf("pipe: %s", strerror(errno));
    if (set_nonblock(p[0], 1) != 0)
        return failf("F_SETFL read end: %s", strerror(errno));
    errno = 0;
    if (read(p[0], &byte, 1) != -1 ||
        (errno != EAGAIN && errno != EWOULDBLOCK))
        return failf("empty nonblocking read did not return EAGAIN");

    capacity = fill_nonblocking(p[1]);
    if (capacity <= 0)
        return failf("could not discover pipe capacity: %s", strerror(errno));
    errno = 0;
    if (write(p[1], &byte, 1) != -1 ||
        (errno != EAGAIN && errno != EWOULDBLOCK))
        return failf("full nonblocking write did not return EAGAIN");
    close(p[0]);
    close(p[1]);
    return 0;
}

static int test_eof_after_last_writer(void)
{
    int data[2], command[2];
    pid_t child;
    char byte;

    if (pipe(data) != 0 || pipe(command) != 0)
        return failf("pipe setup: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        close(data[0]);
        close(command[1]);
        if (read(command[0], &byte, 1) != 1)
            _exit(2);
        close(data[1]);
        _exit(0);
    }

    close(data[1]);
    close(command[0]);
    if (set_nonblock(data[0], 1) != 0)
        return failf("F_SETFL: %s", strerror(errno));
    errno = 0;
    if (read(data[0], &byte, 1) != -1 ||
        (errno != EAGAIN && errno != EWOULDBLOCK))
        return failf("reader saw EOF while another writer was open");
    if (write_exact(command[1], "C", 1) != 0 || !wait_ok(child))
        return failf("writer close coordination failed");
    if (read(data[0], &byte, 1) != 0)
        return failf("last writer close did not produce EOF");
    close(command[1]);
    close(data[0]);
    return 0;
}

static volatile sig_atomic_t sigpipe_seen;

static void sigpipe_handler(int signo)
{
    (void)signo;
    sigpipe_seen = 1;
}

static int install_sigpipe_handler(void)
{
    struct sigaction action;

    memset(&action, 0, sizeof(action));
    action.sa_handler = sigpipe_handler;
    sigemptyset(&action.sa_mask);
    return sigaction(SIGPIPE, &action, NULL);
}

static int test_epipe_and_sigpipe(void)
{
    int p[2];
    char byte = 'X';
    ssize_t result;

    if (pipe(p) != 0 || install_sigpipe_handler() != 0)
        return failf("setup: %s", strerror(errno));
    close(p[0]);
    sigpipe_seen = 0;
    errno = 0;
    result = write(p[1], &byte, 1);
    if (result != -1 || errno != EPIPE || !sigpipe_seen)
        return failf("write returned %ld/%s, SIGPIPE=%d",
                     (long)result, strerror(errno), (int)sigpipe_seen);
    close(p[1]);
    return 0;
}

struct record {
    uint32_t producer;
    uint32_t sequence;
    uint32_t inverse;
    uint32_t checksum;
};

static uint32_t record_checksum(uint32_t producer, uint32_t sequence)
{
    return producer * 0x9e3779b1u ^ sequence * 0x85ebca6bu ^ 0xa55aa55au;
}

static int test_multiple_producers(void)
{
    enum { PRODUCERS = 4, RECORDS = 64 };
    int data[2];
    pid_t children[PRODUCERS];
    unsigned seen[PRODUCERS][RECORDS];
    size_t total = 0;
    unsigned i;

    memset(seen, 0, sizeof(seen));
    if (pipe(data) != 0)
        return failf("pipe: %s", strerror(errno));
    for (i = 0; i < PRODUCERS; i++) {
        children[i] = fork();
        if (children[i] < 0)
            return failf("fork producer %u: %s", i, strerror(errno));
        if (children[i] == 0) {
            unsigned sequence;

            close(data[0]);
            for (sequence = 0; sequence < RECORDS; sequence++) {
                struct record rec = {
                    i, sequence, ~sequence, record_checksum(i, sequence)
                };

                if (write(data[1], &rec, sizeof(rec)) != (ssize_t)sizeof(rec))
                    _exit(2);
            }
            close(data[1]);
            _exit(0);
        }
    }
    close(data[1]);

    while (total < (size_t)PRODUCERS * RECORDS) {
        struct record rec;

        if (read_exact(data[0], &rec, sizeof(rec)) != 0)
            return failf("record stream ended after %zu records", total);
        if (rec.producer >= PRODUCERS || rec.sequence >= RECORDS ||
            rec.inverse != ~rec.sequence ||
            rec.checksum != record_checksum(rec.producer, rec.sequence))
            return failf("corrupt or interleaved record at index %zu", total);
        if (seen[rec.producer][rec.sequence]++ != 0)
            return failf("duplicate producer record");
        total++;
    }
    {
        char extra;
        if (read(data[0], &extra, 1) != 0)
            return failf("extra data remained after fixed records");
    }
    close(data[0]);
    for (i = 0; i < PRODUCERS; i++) {
        if (!wait_ok(children[i]))
            return failf("producer %u failed or made a partial write", i);
    }
    return 0;
}

static int test_blocked_writer_wakes(void)
{
    int data[2], ready[2];
    ssize_t capacity;
    unsigned char *buffer;
    pid_t child;
    char byte;

    if (pipe(data) != 0)
        return failf("pipe: %s", strerror(errno));
    capacity = fill_nonblocking(data[1]);
    if (capacity <= 0 || set_nonblock(data[1], 0) != 0)
        return failf("capacity discovery failed: %s", strerror(errno));
    if (pipe(ready) != 0)
        return failf("coordination pipe: %s", strerror(errno));

    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        close(data[0]);
        close(ready[0]);
        if (write_exact(ready[1], "R", 1) != 0)
            _exit(2);
        if (write(data[1], "W", 1) != 1)
            _exit(3);
        _exit(0);
    }

    close(data[1]);
    close(ready[1]);
    if (read_exact(ready[0], &byte, 1) != 0)
        return failf("writer pre-write handshake failed");
    if (!child_remains_alive(child))
        return failf("write completed while the pipe remained full");

    buffer = malloc((size_t)capacity);
    if (buffer == NULL)
        return failf("malloc for %ld-byte capacity", (long)capacity);
    if (read(data[0], buffer, (size_t)capacity) != capacity) {
        free(buffer);
        return failf("could not drain the discovered capacity");
    }
    free(buffer);
    if (!wait_ok(child))
        return failf("blocked writer did not wake after space was freed");
    if (read(data[0], &byte, 1) != 1 || byte != 'W')
        return failf("woken writer's byte was missing");
    close(data[0]);
    close(ready[0]);
    return 0;
}

static int test_close_wakes_reader(void)
{
    int data[2], ready[2];
    pid_t child;
    char byte;

    if (pipe(data) != 0 || pipe(ready) != 0)
        return failf("pipe setup: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        close(data[1]);
        close(ready[0]);
        if (write_exact(ready[1], "R", 1) != 0)
            _exit(2);
        _exit(read(data[0], &byte, 1) == 0 ? 0 : 3);
    }
    close(data[0]);
    close(ready[1]);
    if (read_exact(ready[0], &byte, 1) != 0)
        return failf("reader readiness handshake failed");
    if (!child_remains_alive(child))
        return failf("empty read completed before the writer was closed");
    close(data[1]);
    close(ready[0]);
    if (!wait_ok(child))
        return failf("closing the last writer did not wake reader with EOF");
    return 0;
}

static int test_close_wakes_writer(void)
{
    int data[2], ready[2];
    ssize_t capacity;
    pid_t child;
    char byte;

    if (pipe(data) != 0)
        return failf("pipe: %s", strerror(errno));
    capacity = fill_nonblocking(data[1]);
    if (capacity <= 0 || set_nonblock(data[1], 0) != 0)
        return failf("capacity discovery failed: %s", strerror(errno));
    if (pipe(ready) != 0)
        return failf("coordination pipe: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        ssize_t result;

        close(data[0]);
        close(ready[0]);
        if (install_sigpipe_handler() != 0)
            _exit(2);
        sigpipe_seen = 0;
        if (write_exact(ready[1], "R", 1) != 0)
            _exit(3);
        errno = 0;
        result = write(data[1], "X", 1);
        _exit(result == -1 && errno == EPIPE && sigpipe_seen ? 0 : 4);
    }
    close(data[1]);
    close(ready[1]);
    if (read_exact(ready[0], &byte, 1) != 0)
        return failf("writer readiness handshake failed");
    if (!child_remains_alive(child))
        return failf("full-pipe write completed before the reader was closed");
    close(data[0]);
    close(ready[0]);
    if (!wait_ok(child))
        return failf("reader close did not wake writer with EPIPE/SIGPIPE");
    return 0;
}

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "direction and basic transfer", test_direction_and_transfer },
    { "reader waits until data arrives", test_blocked_reader_wakes },
    { "nonblocking EAGAIN", test_nonblocking_eagain },
    { "EOF after last writer", test_eof_after_last_writer },
    { "EPIPE and caught SIGPIPE", test_epipe_and_sigpipe },
    // TODO: support atomic pipe ops for buffer size writes/reads
    // { "multiple fixed-record producers", test_multiple_producers },
    { "full-pipe writer waits for space", test_blocked_writer_wakes },
    { "writer close releases waiting reader", test_close_wakes_reader },
    { "reader close releases waiting writer", test_close_wakes_writer },
};

static void run_isolated(const struct test_case *test)
{
    pid_t child;
    pid_t result = 0;
    int status = 0;
    unsigned tick;

    child = fork();
    if (child < 0) {
        printf("FAIL %s (fork: %s)\n", test->name, strerror(errno));
        failed++;
        return;
    }
    if (child == 0) {
        (void)setpgid(0, 0);
        _exit(test->run() == 0 ? 0 : 1);
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
    } else if (result == child && WIFEXITED(status) &&
               WEXITSTATUS(status) == 0) {
        printf("PASS %s\n", test->name);
        passed++;
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
    printf("pipe: %d passed, %d failed\n", passed, failed);
    return failed != 0;
}
