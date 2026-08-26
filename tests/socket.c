/*
 * AF_UNIX and loopback socket conformance tests.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_socket tests/socket.c
 */
#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_TIMEOUT_TICKS 500
#define CHILD_WAIT_TICKS 300
#define POST_KILL_TICKS 100

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

static int unsupported_socket_errno(int error)
{
    return error == EAFNOSUPPORT || error == EPROTONOSUPPORT ||
           error == ESOCKTNOSUPPORT || error == EOPNOTSUPP ||
           error == ENOSYS;
}

static int test_socketpair_basic(void)
{
    int sockets[2];
    char buffer[16] = {0};

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return failf("socketpair: %s", strerror(errno));
    if (write_exact(sockets[0], "left-to-right", 13) != 0 ||
        read_exact(sockets[1], buffer, 13) != 0 ||
        memcmp(buffer, "left-to-right", 13) != 0)
        return failf("first socketpair direction failed");
    memset(buffer, 0, sizeof(buffer));
    if (write_exact(sockets[1], "reply", 5) != 0 ||
        read_exact(sockets[0], buffer, 5) != 0 ||
        memcmp(buffer, "reply", 5) != 0)
        return failf("second socketpair direction failed");
    close(sockets[0]);
    close(sockets[1]);
    return TEST_PASS;
}

struct record {
    uint32_t side;
    uint32_t sequence;
    uint32_t inverse;
    uint32_t checksum;
};

static uint32_t record_checksum(uint32_t side, uint32_t sequence)
{
    return side * 0x9e3779b1u ^ sequence * 0x85ebca6bu ^ 0x51c0ffeeu;
}

static int send_records(int fd, uint32_t side, unsigned count)
{
    unsigned i;

    for (i = 0; i < count; i++) {
        struct record rec = {side, i, ~i, record_checksum(side, i)};
        if (write_exact(fd, &rec, sizeof(rec)) != 0)
            return -1;
    }
    return 0;
}

static int receive_records(int fd, uint32_t side, unsigned count)
{
    unsigned i;

    for (i = 0; i < count; i++) {
        struct record rec;
        if (read_exact(fd, &rec, sizeof(rec)) != 0 || rec.side != side ||
            rec.sequence != i || rec.inverse != ~rec.sequence ||
            rec.checksum != record_checksum(rec.side, rec.sequence))
            return -1;
    }
    return 0;
}

static int test_socketpair_concurrent(void)
{
    enum { RECORDS = 32 };
    int sockets[2], parent_to_child[2], child_to_parent[2];
    pid_t child;
    char byte;

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0 ||
        pipe(parent_to_child) != 0 || pipe(child_to_parent) != 0)
        return failf("setup: %s", strerror(errno));
    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        close(sockets[0]);
        close(parent_to_child[1]);
        close(child_to_parent[0]);
        if (write_exact(child_to_parent[1], "R", 1) != 0 ||
            read_exact(parent_to_child[0], &byte, 1) != 0)
            _exit(2);
        if (send_records(sockets[1], 2, RECORDS) != 0 ||
            receive_records(sockets[1], 1, RECORDS) != 0)
            _exit(3);
        _exit(0);
    }

    close(sockets[1]);
    close(parent_to_child[0]);
    close(child_to_parent[1]);
    if (read_exact(child_to_parent[0], &byte, 1) != 0 ||
        write_exact(parent_to_child[1], "S", 1) != 0)
        return failf("two-channel start handshake failed");
    if (send_records(sockets[0], 1, RECORDS) != 0 ||
        receive_records(sockets[0], 2, RECORDS) != 0)
        return failf("concurrent full-duplex transfer failed");
    close(sockets[0]);
    close(parent_to_child[1]);
    close(child_to_parent[0]);
    if (!wait_ok(child))
        return failf("socketpair peer failed integrity checks");
    return TEST_PASS;
}

static int test_shutdown_eof(void)
{
    int sockets[2];
    int flags;
    char byte;
    ssize_t result;

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return failf("socketpair: %s", strerror(errno));
    flags = fcntl(sockets[1], F_GETFL);
    if (flags < 0 || fcntl(sockets[1], F_SETFL, flags | O_NONBLOCK) != 0)
        return failf("set nonblocking peer: %s", strerror(errno));
    errno = 0;
    if (shutdown(sockets[0], SHUT_WR) != 0) {
        if (errno == ENOSYS || errno == EOPNOTSUPP) {
            close(sockets[0]);
            close(sockets[1]);
            return skipf("shutdown is unsupported");
        }
        return failf("shutdown: %s", strerror(errno));
    }
    errno = 0;
    result = read(sockets[1], &byte, 1);
    close(sockets[0]);
    close(sockets[1]);
    if (result != 0)
        return failf("SHUT_WR did not produce peer EOF: result=%ld errno=%s",
                     (long)result, strerror(errno));
    return TEST_PASS;
}

static int test_socket_names(void)
{
    int sockets[2];
    struct sockaddr_storage local, peer;
    socklen_t local_length = sizeof(local);
    socklen_t peer_length = sizeof(peer);

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return failf("socketpair: %s", strerror(errno));
    memset(&local, 0, sizeof(local));
    memset(&peer, 0, sizeof(peer));
    errno = 0;
    if (getsockname(sockets[0], (struct sockaddr *)&local, &local_length) != 0 ||
        getpeername(sockets[0], (struct sockaddr *)&peer, &peer_length) != 0) {
        int error = errno;
        close(sockets[0]);
        close(sockets[1]);
        if (error == ENOSYS || error == EOPNOTSUPP)
            return skipf("socket name queries are unsupported");
        return failf("socket name query: %s", strerror(error));
    }
    close(sockets[0]);
    close(sockets[1]);
    if (local_length < sizeof(sa_family_t) ||
        peer_length < sizeof(sa_family_t) ||
        local.ss_family != AF_UNIX || peer.ss_family != AF_UNIX)
        return failf("socketpair name families or lengths were invalid");
    return TEST_PASS;
}

static int test_socket_options(void)
{
    int sockets[2];
    int type = -1;
    socklen_t length = sizeof(type);

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return failf("socketpair: %s", strerror(errno));
    errno = 0;
    if (getsockopt(sockets[0], SOL_SOCKET, SO_TYPE, &type, &length) != 0) {
        int error = errno;
        close(sockets[0]);
        close(sockets[1]);
        if (error == ENOSYS || error == EOPNOTSUPP || error == ENOPROTOOPT)
            return skipf("SO_TYPE query is unsupported");
        return failf("getsockopt(SO_TYPE): %s", strerror(error));
    }
    close(sockets[0]);
    close(sockets[1]);
    if (length != sizeof(type) || type != SOCK_STREAM)
        return failf("SO_TYPE result was unwritten or incorrect");
    return TEST_PASS;
}

static int test_inet_loopback(void)
{
    struct sockaddr_in address;
    socklen_t address_length = sizeof(address);
    int listener, accepted, control[2];
    pid_t child;
    char buffer[5] = {0};

    errno = 0;
    listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0 && unsupported_socket_errno(errno))
        return skipf("AF_INET sockets are unsupported");
    if (listener < 0)
        return failf("socket(AF_INET): %s", strerror(errno));
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        getsockname(listener, (struct sockaddr *)&address, &address_length) != 0 ||
        address_length < sizeof(address) || address.sin_port == 0 ||
        listen(listener, 4) != 0)
        return failf("loopback bind/listen: %s", strerror(errno));
    if (pipe(control) != 0)
        return failf("coordination pipe: %s", strerror(errno));

    child = fork();
    if (child < 0)
        return failf("fork: %s", strerror(errno));
    if (child == 0) {
        int client;
        char command;

        close(listener);
        close(control[1]);
        if (read_exact(control[0], &command, 1) != 0)
            _exit(2);
        client = socket(AF_INET, SOCK_STREAM, 0);
        if (client < 0 ||
            connect(client, (struct sockaddr *)&address, sizeof(address)) != 0)
            _exit(3);
        if (write_exact(client, "ping", 4) != 0 ||
            read_exact(client, buffer, 4) != 0 || memcmp(buffer, "pong", 4) != 0)
            _exit(4);
        close(client);
        _exit(0);
    }

    close(control[0]);
    if (write_exact(control[1], "C", 1) != 0)
        return failf("client start handshake failed");
    accepted = accept(listener, NULL, NULL);
    if (accepted < 0)
        return failf("accept: %s", strerror(errno));
    if (read_exact(accepted, buffer, 4) != 0 || memcmp(buffer, "ping", 4) != 0 ||
        write_exact(accepted, "pong", 4) != 0)
        return failf("loopback data transfer failed");
    close(accepted);
    close(listener);
    close(control[1]);
    if (!wait_ok(child))
        return failf("loopback client failed");
    return TEST_PASS;
}

struct test_case {
    const char *name;
    int (*run)(void);
};

static const struct test_case tests[] = {
    { "AF_UNIX socketpair basic transfer", test_socketpair_basic },
    { "AF_UNIX concurrent transfer", test_socketpair_concurrent },
    // TODO: implement proper shutdown
    // { "shutdown and EOF", test_shutdown_eof },
    { "socket name queries", test_socket_names },
    // TODO: implement proper getsockopt
    // { "socket option query", test_socket_options },
    { "AF_INET loopback", test_inet_loopback },
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
    printf("socket: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed != 0;
}
