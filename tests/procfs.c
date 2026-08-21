/*
 * KFS procfs test suite.
 *
 * Static i386-musl build:
 *   zig cc -target x86-linux-musl -static -O2 -o test_procfs tests/procfs.c
 */
#define _GNU_SOURCE

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define BUFFER_SIZE 16384
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

enum result { TEST_PASS, TEST_FAIL, TEST_SKIP };

static int passed;
static int failed;
static int skipped;

static ssize_t read_file(const char *path, char *buf, size_t capacity)
{
    size_t used = 0;
    int fd = open(path, O_RDONLY | O_CLOEXEC);

    if (fd < 0)
        return -1;
    while (used + 1 < capacity) {
        ssize_t n = read(fd, buf + used, capacity - used - 1);

        if (n > 0) {
            used += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0) {
            int saved = errno;
            close(fd);
            errno = saved;
            return -1;
        }
        break;
    }
    close(fd);
    buf[used] = '\0';
    return (ssize_t)used;
}

static int parse_task_stat(const char *buf, pid_t expected,
                           pid_t expected_parent, pid_t expected_group)
{
    char *end;
    const char *right;
    long pid;
    long ppid;
    long pgid;
    char state;

    errno = 0;
    pid = strtol(buf, &end, 10);
    if (errno != 0 || end == buf || pid != (long)expected)
        return -1;
    if (end[0] != ' ' || end[1] != '(')
        return -1;
    right = strrchr(end + 2, ')');
    if (right == NULL || right == end + 2 || right[1] != ' ')
        return -1;
    if (sscanf(right + 1, " %c %ld %ld", &state, &ppid, &pgid) != 3)
        return -1;
    if (strchr("RSDTZIX", state) == NULL || ppid < 0 || pgid <= 0)
        return -1;
    if (expected_parent >= 0 && ppid != (long)expected_parent)
        return -1;
    if (expected_group >= 0 && pgid != (long)expected_group)
        return -1;
    return 0;
}

static enum result read_optional(const char *path, char *buf, size_t capacity,
                                 ssize_t *length)
{
    *length = read_file(path, buf, capacity);
    if (*length < 0 && (errno == ENOENT || errno == ENOTDIR))
        return TEST_SKIP;
    return *length < 0 ? TEST_FAIL : TEST_PASS;
}

static enum result test_proc_directory(void)
{
    DIR *dir = opendir("/proc");
    struct dirent *entry;
    int saw_stat = 0;
    int saw_numeric = 0;
    unsigned count = 0;

    if (dir == NULL)
        return TEST_FAIL;
    while (count++ < 4096 && (entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, "stat") == 0)
            saw_stat = 1;
        if (isdigit((unsigned char)entry->d_name[0]))
            saw_numeric = 1;
    }
    closedir(dir);
    return saw_stat && saw_numeric && count > 1 ? TEST_PASS : TEST_FAIL;
}

static enum result test_numeric_stat(void)
{
    char path[64];
    char buf[2048];

    snprintf(path, sizeof(path), "/proc/%ld/stat", (long)getpid());
    if (read_file(path, buf, sizeof(buf)) <= 0)
        return TEST_FAIL;
    return parse_task_stat(buf, getpid(), getppid(), getpgid(0)) == 0 ?
           TEST_PASS : TEST_FAIL;
}

static enum result test_self_stat(void)
{
    char buf[2048];
    ssize_t n = read_file("/proc/self/stat", buf, sizeof(buf));

    if (n < 0 && (errno == ENOENT || errno == ENOTDIR))
        return TEST_SKIP;
    if (n <= 0)
        return TEST_FAIL;
    return parse_task_stat(buf, getpid(), getppid(), getpgid(0)) == 0 ?
           TEST_PASS : TEST_FAIL;
}

static long status_number(const char *buf, const char *field)
{
    size_t length = strlen(field);
    const char *line = buf;

    while (line != NULL && *line != '\0') {
        if (strncmp(line, field, length) == 0 && line[length] == ':') {
            char *end;
            long value;

            errno = 0;
            value = strtol(line + length + 1, &end, 10);
            if (errno != 0 || end == line + length + 1 || value < 0)
                return -1;
            return value;
        }
        line = strchr(line, '\n');
        if (line != NULL)
            line++;
    }
    return -1;
}

static enum result test_status(void)
{
    char path[64];
    char buf[8192];
    ssize_t n;

    snprintf(path, sizeof(path), "/proc/%ld/status", (long)getpid());
    n = read_file(path, buf, sizeof(buf));
    if (n < 0 && errno == ENOENT)
        return TEST_SKIP;
    if (n <= 0)
        return TEST_FAIL;
    if (status_number(buf, "Pid") != (long)getpid())
        return TEST_FAIL;
    if (status_number(buf, "PPid") != (long)getppid())
        return TEST_FAIL;
    if (status_number(buf, "Tgid") != (long)getpid())
        return TEST_FAIL;
    return TEST_PASS;
}

static enum result test_cmdline(void)
{
    char path[64];
    char buf[2048];
    ssize_t n;

    snprintf(path, sizeof(path), "/proc/%ld/cmdline", (long)getpid());
    n = read_file(path, buf, sizeof(buf));
    if (n < 0 && errno == ENOENT)
        return TEST_SKIP;
    if (n < 0)
        return TEST_FAIL;
    if (n == 0)
        return TEST_SKIP;
    return buf[0] != '\0' ? TEST_PASS : TEST_FAIL;
}

static enum result test_meminfo(void)
{
    char buf[BUFFER_SIZE];
    unsigned long total, free_kb, available;
    ssize_t n;
    enum result result = read_optional("/proc/meminfo", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n == 0 || sscanf(buf,
        "MemTotal: %lu kB\nMemFree: %lu kB\nMemAvailable: %lu kB",
        &total, &free_kb, &available) != 3 || total == 0)
        return TEST_FAIL;
    return free_kb <= total && available <= total ? TEST_PASS : TEST_FAIL;
}

static enum result test_system_stat(void)
{
    char buf[BUFFER_SIZE];
    unsigned long user, nice, system, idle;
    unsigned long processes, running, blocked;
    const char *line;
    ssize_t n;
    enum result result = read_optional("/proc/stat", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n == 0)
        return TEST_FAIL;
    if (sscanf(buf, "cpu %lu %lu %lu %lu", &user, &nice, &system, &idle) != 4)
        return TEST_FAIL;
    line = strstr(buf, "processes ");
    if (line == NULL || sscanf(line, "processes %lu", &processes) != 1)
        return TEST_FAIL;
    line = strstr(buf, "procs_running ");
    if (line == NULL || sscanf(line, "procs_running %lu", &running) != 1)
        return TEST_FAIL;
    line = strstr(buf, "procs_blocked ");
    if (line == NULL || sscanf(line, "procs_blocked %lu", &blocked) != 1)
        return TEST_FAIL;
    return running > 0 && running <= processes && blocked <= processes ?
           TEST_PASS : TEST_FAIL;
}

static enum result test_uptime(void)
{
    char buf[256];
    double uptime, idle;
    ssize_t n;
    enum result result = read_optional("/proc/uptime", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n == 0)
        return TEST_FAIL;
    if (sscanf(buf, "%lf %lf", &uptime, &idle) != 2)
        return TEST_FAIL;
    return uptime == uptime && idle == idle && uptime >= 0.0 && idle >= 0.0 ?
           TEST_PASS : TEST_FAIL;
}

static enum result test_loadavg(void)
{
    char buf[256];
    double one, five, fifteen;
    unsigned running, total;
    long last;
    ssize_t n;
    enum result result = read_optional("/proc/loadavg", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n == 0)
        return TEST_FAIL;
    if (sscanf(buf, "%lf %lf %lf %u/%u %ld",
               &one, &five, &fifteen, &running, &total, &last) != 6)
        return TEST_FAIL;
    return one == one && five == five && fifteen == fifteen &&
           one >= 0.0 && five >= 0.0 && fifteen >= 0.0 &&
           total > 0 && running <= total && last > 0 ? TEST_PASS : TEST_FAIL;
}

static enum result test_filesystems(void)
{
    char buf[BUFFER_SIZE];
    ssize_t n;
    enum result result = read_optional("/proc/filesystems", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n <= 0)
        return TEST_FAIL;
    return strstr(buf, "proc") != NULL && strchr(buf, '\n') != NULL ?
           TEST_PASS : TEST_FAIL;
}

static enum result test_mounts(void)
{
    char buf[BUFFER_SIZE];
    char source[128], target[128], type[64], options[256];
    unsigned dump, passno;
    char *line;
    ssize_t n;
    enum result result = read_optional("/proc/mounts", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n <= 0)
        return TEST_FAIL;
    line = strstr(buf, " /proc ");
    if (line == NULL)
        return TEST_FAIL;
    while (line > buf && line[-1] != '\n')
        line--;
    if (sscanf(line, "%127s %127s %63s %255s %u %u",
               source, target, type, options, &dump, &passno) != 6)
        return TEST_FAIL;
    return strcmp(target, "/proc") == 0 && strstr(type, "proc") != NULL ?
           TEST_PASS : TEST_FAIL;
}

static enum result test_modules(void)
{
    char buf[BUFFER_SIZE];
    char name[128], dependencies[128], state[32], address[32];
    unsigned long size;
    unsigned references;
    ssize_t n;
    enum result result = read_optional("/proc/modules", buf, sizeof(buf), &n);

    if (result != TEST_PASS)
        return result;
    if (n == 0)
        return TEST_PASS;
    return sscanf(buf, "%127s %lu %u %127s %31s %31s",
                  name, &size, &references, dependencies, state, address) == 6 &&
           name[0] != '\0' && state[0] != '\0' ? TEST_PASS : TEST_FAIL;
}

static enum result test_repeated_reads(void)
{
    char path[64];
    char buf[2048];
    unsigned i;

    snprintf(path, sizeof(path), "/proc/%ld/stat", (long)getpid());
    for (i = 0; i < 16; i++) {
        if (read_file(path, buf, sizeof(buf)) <= 0)
            return TEST_FAIL;
        if (parse_task_stat(buf, getpid(), getppid(), getpgid(0)) != 0)
            return TEST_FAIL;
    }
    return TEST_PASS;
}

static int wait_bounded(pid_t pid, int *status)
{
    unsigned tick;

    for (tick = 0; tick < 300; tick++) {
        pid_t result = waitpid(pid, status, WNOHANG);

        if (result == pid)
            return 0;
        if (result < 0 && errno != EINTR)
            break;
        usleep(10000);
    }
    kill(pid, SIGKILL);
    for (tick = 0; tick < 100; tick++) {
        pid_t result = waitpid(pid, status, WNOHANG);

        if (result == pid)
            return -1;
        usleep(10000);
    }
    return -1;
}

static enum result test_concurrent_reads(void)
{
    pid_t children[4];
    unsigned created = 0;
    unsigned i;
    int bad = 0;

    for (i = 0; i < ARRAY_SIZE(children); i++) {
        pid_t pid = fork();

        if (pid == 0) {
            char path[64];
            char buf[4096];
            unsigned iteration;

            snprintf(path, sizeof(path), "/proc/%ld/stat", (long)getpid());
            for (iteration = 0; iteration < 12; iteration++) {
                if (read_file(path, buf, sizeof(buf)) <= 0 ||
                    parse_task_stat(buf, getpid(), getppid(), getpgid(0)) != 0 ||
                    read_file("/proc/stat", buf, sizeof(buf)) <= 0)
                    _exit(1);
            }
            _exit(0);
        }
        if (pid < 0)
            break;
        children[created++] = pid;
    }
    if (created == 0)
        return TEST_SKIP;
    for (i = 0; i < created; i++) {
        int status = 0;

        if (wait_bounded(children[i], &status) != 0 ||
            !WIFEXITED(status) || WEXITSTATUS(status) != 0)
            bad = 1;
    }
    return bad ? TEST_FAIL : TEST_PASS;
}

static enum result test_process_lifecycle(void)
{
    int ready[2];
    int release[2];
    pid_t pid;
    char path[64];
    char buf[2048];
    struct pollfd pollfd;
    int status = 0;
    unsigned i;

    if (pipe(ready) != 0)
        return TEST_SKIP;
    if (pipe(release) != 0) {
        close(ready[0]);
        close(ready[1]);
        return TEST_SKIP;
    }
    pid = fork();
    if (pid == 0) {
        char byte = 'r';

        close(ready[0]);
        close(release[1]);
        if (write(ready[1], &byte, 1) != 1)
            _exit(1);
        if (read(release[0], &byte, 1) != 1)
            _exit(2);
        _exit(0);
    }
    close(ready[1]);
    close(release[0]);
    if (pid < 0) {
        close(ready[0]);
        close(release[1]);
        return TEST_SKIP;
    }
    pollfd.fd = ready[0];
    pollfd.events = POLLIN;
    pollfd.revents = 0;
    if (poll(&pollfd, 1, 2000) <= 0 || read(ready[0], buf, 1) != 1) {
        kill(pid, SIGKILL);
        wait_bounded(pid, &status);
        close(ready[0]);
        close(release[1]);
        return TEST_FAIL;
    }
    close(ready[0]);
    snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
    if (read_file(path, buf, sizeof(buf)) <= 0 ||
        parse_task_stat(buf, pid, getpid(), getpgid(pid)) != 0) {
        write(release[1], "x", 1);
        close(release[1]);
        wait_bounded(pid, &status);
        return TEST_FAIL;
    }
    if (write(release[1], "x", 1) != 1) {
        close(release[1]);
        kill(pid, SIGKILL);
        wait_bounded(pid, &status);
        return TEST_FAIL;
    }
    close(release[1]);
    if (wait_bounded(pid, &status) != 0 ||
        !WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return TEST_FAIL;

    for (i = 0; i < 100; i++) {
        if (read_file(path, buf, sizeof(buf)) < 0 && errno == ENOENT)
            return TEST_PASS;
        usleep(10000);
    }
    return TEST_FAIL;
}

struct test_case {
    const char *name;
    enum result (*run)(void);
};

static const struct test_case tests[] = {
    { "open and enumerate /proc", test_proc_directory },
    { "numeric pid stat matches getpid", test_numeric_stat },
    { "/proc/self/stat matches getpid", test_self_stat },
    { "pid status fields", test_status },
    { "pid cmdline", test_cmdline },
    { "parse meminfo", test_meminfo },
    { "parse system stat", test_system_stat },
    { "parse uptime", test_uptime },
    { "parse loadavg", test_loadavg },
    { "parse filesystems", test_filesystems },
    { "parse mounts", test_mounts },
    { "read modules", test_modules },
    { "repeated pid reads", test_repeated_reads },
    { "concurrent proc reads", test_concurrent_reads },
    { "process lifecycle visibility", test_process_lifecycle },
};

int main(void)
{
    size_t i;

    setvbuf(stdout, NULL, _IONBF, 0);
    puts("procfs suite");
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
            printf("SKIP %s [entry or facility unavailable]\n", tests[i].name);
            skipped++;
        } else {
            if (saved_errno != 0)
                printf("FAIL %s [errno=%d: %s]\n",
                       tests[i].name, saved_errno, strerror(saved_errno));
            else
                printf("FAIL %s [format or consistency mismatch]\n",
                       tests[i].name);
            failed++;
        }
    }
    printf("SUMMARY pass=%d fail=%d skip=%d\n", passed, failed, skipped);
    return failed != 0;
}
