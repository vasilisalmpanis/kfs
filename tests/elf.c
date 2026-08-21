/*
 * ELF image/startup test suite (i386 Linux ABI)
 *
 * Build (static i386 musl):
 *   zig cc -target x86-linux-musl -static -O2 -pthread \
 *     -o test_elf tests/elf.c
 *
 * Self-exec resolves argv[0] through cwd and PATH without /proc. If neither
 * works, invoke this suite with an explicit executable pathname.
 */
#define _GNU_SOURCE

#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define TEST_SKIP 77

static unsigned char bss_area[8192];
static unsigned char initialized_data[] = {
    0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe
};
static const unsigned char initialized_expected[] = {
    0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe
};
static const char *self_path;
static char self_path_storage[PATH_MAX];
extern char **environ;

struct aux_entry {
    uintptr_t type;
    uintptr_t value;
};

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

static int all_bss_zero(void)
{
    size_t i;

    for (i = 0; i < sizeof(bss_area); i++) {
        if (bss_area[i] != 0)
            return 0;
    }
    return 1;
}

static int self_exec_mode(int argc, char **argv)
{
    const char *mark;

    if (argc < 2 || strcmp(argv[1], "--elf-self-probe") != 0)
        return -1;
    mark = getenv("KFS_ELF_EXEC_MARK");
    if (argc != 3 || strcmp(argv[2], "fresh-image") != 0 ||
        mark == NULL || strcmp(mark, "present") != 0)
        return 2;
    if (!all_bss_zero())
        return 3;
    if (memcmp(initialized_data, initialized_expected,
               sizeof(initialized_data)) != 0)
        return 4;
    return 0;
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
            if (access(self_path_storage, R_OK | X_OK) == 0)
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
            if (access(self_path_storage, R_OK | X_OK) == 0)
                return self_path_storage;
        }
        path = end != NULL ? end + 1 : NULL;
    }
    return argv0;
}

static int test_bss_zeroing(void)
{
    if (!all_bss_zero())
        return failf("BSS contained nonzero data at startup");
    bss_area[0] = 0x5a;
    bss_area[sizeof(bss_area) - 1] = 0xa5;
    if (bss_area[0] != 0x5a || bss_area[sizeof(bss_area) - 1] != 0xa5)
        return failf("BSS was not writable");
    return 0;
}

static int test_initialized_data(void)
{
    if (memcmp(initialized_data, initialized_expected,
               sizeof(initialized_data)) != 0)
        return failf("initialized data did not match the ELF image");
    initialized_data[0] ^= 0xff;
    if (initialized_data[0] != (unsigned char)(initialized_expected[0] ^ 0xff))
        return failf("initialized writable data was not writable");
    return 0;
}

static int startup_argc;
static char **startup_argv;

static int test_stack_argv_environment(void)
{
    char **entry;
    size_t env_count = 0;

    if (startup_argc < 1 || startup_argv == NULL || startup_argv[0] == NULL ||
        startup_argv[startup_argc] != NULL || startup_argv[0][0] == '\0')
        return failf("argc/argv startup layout was invalid");
    if (environ == NULL)
        return failf("environment pointer was NULL");
    for (entry = environ; *entry != NULL && env_count < 4096; entry++) {
        if (strchr(*entry, '=') == NULL)
            return failf("environment entry lacked '='");
        env_count++;
    }
    if (env_count == 4096 || *entry != NULL)
        return failf("environment was not NULL terminated");
    if (((uintptr_t)startup_argv & (sizeof(void *) - 1)) != 0)
        return failf("argv pointer array was not naturally aligned");
    return 0;
}

static int find_aux(uintptr_t key, uintptr_t *value)
{
    char **entry = environ;
    struct aux_entry *aux;
    unsigned i;

    while (*entry != NULL)
        entry++;
    aux = (struct aux_entry *)(entry + 1);
    for (i = 0; i < 128; i++) {
        if (aux[i].type == AT_NULL)
            return 0;
        if (aux[i].type == key) {
            *value = aux[i].value;
            return 1;
        }
    }
    return 0;
}

static int test_auxiliary_vector(void)
{
    uintptr_t pagesz;
    uintptr_t phdr;
    uintptr_t phent;
    uintptr_t phnum;
    uintptr_t entry;
    uintptr_t base;
    uintptr_t sysinfo;
    unsigned long via_getauxval;
    long host_page_size = sysconf(_SC_PAGESIZE);

    if (!find_aux(AT_PAGESZ, &pagesz) || !find_aux(AT_PHDR, &phdr) ||
        !find_aux(AT_PHENT, &phent) || !find_aux(AT_PHNUM, &phnum) ||
        !find_aux(AT_ENTRY, &entry) || !find_aux(AT_BASE, &base))
        return failf("required auxv entries were absent");
    errno = 0;
    via_getauxval = getauxval(AT_PAGESZ);
    if (via_getauxval == 0 || via_getauxval != pagesz)
        return failf("getauxval(AT_PAGESZ) disagreed with auxv");
    if (host_page_size <= 0 || pagesz != (uintptr_t)host_page_size ||
        (pagesz & (pagesz - 1)) != 0)
        return failf("AT_PAGESZ had invalid value %lu", (unsigned long)pagesz);
#if UINTPTR_MAX == UINT32_MAX
    if (phent != sizeof(Elf32_Phdr))
        return failf("AT_PHENT was %lu, expected %zu",
                     (unsigned long)phent, sizeof(Elf32_Phdr));
#else
    if (phent != sizeof(Elf64_Phdr))
        return failf("AT_PHENT was %lu, expected %zu",
                     (unsigned long)phent, sizeof(Elf64_Phdr));
#endif
    if (phdr == 0 || phnum == 0 || entry == 0 ||
        (phdr & (sizeof(uintptr_t) - 1)) != 0)
        return failf("AT_PHDR/AT_PHNUM/AT_ENTRY values were invalid");
    if (base != 0 && (base & (pagesz - 1)) != 0)
        return failf("AT_BASE was not page aligned");
    if (find_aux(AT_SYSINFO_EHDR, &sysinfo) && sysinfo != 0 &&
        (sysinfo & (pagesz - 1)) != 0)
        return failf("AT_SYSINFO_EHDR was not page aligned");
    return 0;
}

static int test_self_exec_fresh_image(void)
{
    pid_t pid = fork();

    if (pid < 0)
        return failf("fork failed: %s", strerror(errno));
    if (pid == 0) {
        char *const args[] = {
            (char *)self_path, "--elf-self-probe", "fresh-image", NULL
        };
        char *const env[] = { "KFS_ELF_EXEC_MARK=present", NULL };

        memset(bss_area, 0xa5, sizeof(bss_area));
        memset(initialized_data, 0x5a, sizeof(initialized_data));
        execve(self_path, args, env);
        _exit(100);
    }
    if (!wait_status(pid, 0))
        return failf("self-exec did not load a fresh ELF image");
    return 0;
}

static int test_truncated_elf_rejected(void)
{
    char path[96];
    unsigned char prefix[16];
    int source;
    int output;
    ssize_t count;
    char *args[2];
    char *const env[] = { "KFS_BAD_ELF=1", NULL };
    int saved_errno;

    snprintf(path, sizeof(path), "/tmp/kfs-elf-truncated-%ld", (long)getpid());
    source = open(self_path, O_RDONLY);
    if (source < 0)
        return failf("open self failed: %s", strerror(errno));
    count = read(source, prefix, sizeof(prefix));
    close(source);
    if (count != (ssize_t)sizeof(prefix))
        return failf("could not read ELF prefix");
    output = open(path, O_WRONLY | O_CREAT | O_EXCL, 0700);
    if (output < 0) {
        if (errno == ENOENT || errno == EACCES || errno == EROFS)
            return TEST_SKIP;
        return failf("create truncated ELF failed: %s", strerror(errno));
    }
    if (write(output, prefix, sizeof(prefix)) != (ssize_t)sizeof(prefix)) {
        close(output);
        unlink(path);
        return failf("write truncated ELF failed: %s", strerror(errno));
    }
    close(output);
    args[0] = path;
    args[1] = NULL;
    errno = 0;
    if (execve(path, args, env) != -1) {
        unlink(path);
        return failf("truncated ELF unexpectedly executed");
    }
    saved_errno = errno;
    unlink(path);
    if (saved_errno != ENOEXEC)
        return failf("truncated ELF returned errno %d, expected ENOEXEC",
                     saved_errno);
    return 0;
}

struct test_case {
    const char *name;
    int (*fn)(void);
};

static const struct test_case tests[] = {
    { "BSS zeroing", test_bss_zeroing },
    { "initialized data", test_initialized_data },
    { "initial stack argv/environment", test_stack_argv_environment },
    { "auxv presence, values, and alignment", test_auxiliary_vector },
    { "self-exec fresh image", test_self_exec_fresh_image },
    { "truncated ELF exec rejection", test_truncated_elf_rejected },
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
        printf("SKIP  %s [safe self-copy unavailable]\n", test->name);
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

    mode = self_exec_mode(argc, argv);
    if (mode >= 0)
        return mode;
    /* If cwd/PATH cannot resolve a bare argv[0], invoke with a pathname. */
    self_path = resolve_self_path(argv[0]);
    startup_argc = argc;
    startup_argv = argv;
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    for (i = 0; i < ARRAY_SIZE(tests); i++)
        run_test(&tests[i], &passed, &failed, &skipped);
    printf("SUMMARY elf: %d passed, %d failed, %d skipped\n",
           passed, failed, skipped);
    return failed ? 1 : 0;
}
