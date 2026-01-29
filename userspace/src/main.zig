const os = @import("std").os;
const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");
const shell = @import("./shell.zig");

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = myLogFn,
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    var buf: [1000]u8 = undefined;
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ format;
    const data = std.fmt.bufPrint(&buf, prefix, args) catch "";    
    _ = os.linux.write(2, data.ptr, data.len);
}

fn serial(comptime format: []const u8, args: anytype) void {
    std.debug.print(format, args);
}

fn screen(comptime format: []const u8, args: anytype) void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    stdout.print(format, args) catch {};
    stdout.flush() catch {};
}

fn testWait() void {
    const pid = std.posix.fork() catch |err| {
        serial("fork error {any}\n", .{err});
        return;
    };
    if (pid == 0) {
        std.posix.exit(11);
    } else {
        serial("[CHILD] waitpid {any} result: {any}\n", .{
            pid,
            std.posix.waitpid(pid, 0)
        });
    }
}

fn customHandler(_: i32) callconv(.c) void {
    serial("[CHILD] Custom handler for child process\n", .{});
}

fn allocateMemory() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const ptr = allocator.create(i32) catch null;
    ptr.?.* = 77;
    std.debug.print(
        "[CHILD] Child process mapped memory: ptr={*} {d}\n",
        .{ptr, ptr.?.*}
    );
}

fn ipc(sock_fd: i32) void {
    var message: [10]u8 = .{0} ** 10;
    while (os.linux.recvfrom(
        sock_fd,
        @ptrCast(&message),
        10,
        0,
        null,
        null
    ) == 0)
    {}
    serial("[CHILD] reached IPC\n", .{});
    serial("[CHILD] received: {s}\n", .{message[0..10]});
}

fn pidUid(task: [] const u8) void {
    const uid: u32 = os.linux.getuid();  
    const pid: i32 = os.linux.getpid();  
    serial("{s} UID: {d} PID: {d}\n", .{task, uid, pid});
}

fn setAction() void {
    const action: std.posix.Sigaction = .{
        .handler = .{ .handler = &customHandler },
        .mask = .{0} ** 2,
        .flags = 0,
    };
    _ = os.linux.sigaction(std.c.SIG.ABRT, &action, null);
}

fn childProcess(sock_fd: i32) void {
    setAction();
    testWait();
    pidUid("[CHILD]");
    ipc(sock_fd);
    allocateMemory();

    _ = std.posix.sendto(
        sock_fd,
        "test send",
        0,
        null,
        0
    ) catch |err| brk: {
        serial("[CHILD] error: {any}", .{err});
        break :brk 0;
    };
    // Child Process dies.
    os.linux.exit(5); 
}

const DIR = struct
{
    tell: u32 = 0,
    fd: i32 = 0,
    buf_pos: u32 = 0,
    buf_end: u32 = 0,
    buf: [2048]u8 = .{0} ** 2048,
};

fn opendir(_: [*]const u8, dir: *DIR) !void {
    const fd: i32 = @intCast(std.os.linux.open("/ext2", .{ .CREAT = true }, 0o444));
    if (fd < 0) return error.WTF;
    dir.fd = fd;
    dir.buf_pos = 0;
    dir.buf_end = 0;
    dir.buf = .{0} ** 2048;
}

const LinuxDirent = struct {
        ino: u32,
        off: u32,
        reclen: u16,
        type: u8,
};

const ZigDirent = struct {
    dirent: *LinuxDirent,
    name: []u8,
};

fn readdir(dir: *DIR) ?ZigDirent {
    if (dir.buf_pos >= dir.buf_end) {
        const len: i32 = @intCast(std.os.linux.getdents64(dir.fd, @ptrCast(&dir.buf), 2048));
        if (len <= 0) {
            return null;
        }
        dir.buf_end = @intCast(len);
        dir.buf_pos = 0;
    }
    const dirent: *LinuxDirent = @ptrFromInt(@intFromPtr(&dir.buf) + dir.buf_pos);
    const name_len = dirent.reclen - 12;
    const zig_dir = ZigDirent{
        .dirent = dirent,
        .name = dir.buf[dir.buf_pos + 11 .. dir.buf_pos + 11 + name_len],
    };
    dir.buf_pos += dirent.reclen;
    dir.tell += dirent.off;
    return zig_dir;
}

fn test_getdents() void {
    var dir: DIR = DIR{};
    var err: u32 = 0;
    opendir("/ext2", &dir) catch {
        serial("[parent] error opening dir\n", .{});
        err = 1;
    };
    if (err == 0) {
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
        if (readdir(&dir)) |entity| {
            serial("[parent] readdir entity {any} {s}\n", .{entity.dirent, entity.name});
        }
    }
}

pub fn run_test() void {
    var fds: [2]i32 = .{0, 0};
    _ = os.linux.socketpair(
        os.linux.AF.UNIX,
        os.linux.SOCK.STREAM,
        0,
        &fds
    );
    const pid = std.posix.fork() catch {
        return ;
    };
    if (pid == 0) {
        childProcess(fds[1]);
        std.posix.exit(0);
    }
    // IPC in parent
    _ = std.posix.sendto(
        fds[0],
        "test send",
        0,
        null,
        0
    ) catch |err| brk: {
        serial("[PARENT] error: {any}", .{err});
        break :brk 0;
    };

    // // Waiting for child to send message
    var buf: [30]u8 = .{0} ** 30;
    while (
        std.posix.recvfrom(
            fds[0],
            @ptrCast(&buf),
            0,
            null,
            null
        ) catch |err| blk: {
            serial("error receiving: {any}", .{err});
            break :blk 1;
        } == 0
    ) {}

    serial("[PARENT] received from child {s}\n", .{buf});
    _ = os.linux.kill(@intCast(pid), os.linux.SIG.ABRT);
    _ = std.posix.wait4(pid, 0, null);
}

pub fn load_modules() !void {
    const fd = try std.posix.open(
        "/etc/modules",
        std.os.linux.O{.ACCMODE = .RDONLY},
        0o444
    );
    var file = std.fs.File{
        .handle = fd
    };
    var reader_buff: [256]u8 = undefined;
    var reader = file.reader(&reader_buff);
    var r = &reader.interface;
    while (true) {
        const line = r.takeDelimiterExclusive('\n') catch |err| {
            switch (err) {
                error.EndOfStream => return,
                else => return err,
            }
            return err;
        };
        if (line.len == 0) {
            return;
        }
        r.seek += 1;
        if (line[0] == '#') {
            continue ;
        }
        var dir_fd: i32 = undefined;
        if (line[0] == '/') {
            dir_fd = -100;
        } else {
            dir_fd = try std.posix.open(
                "/modules",
                std.os.linux.O{.DIRECTORY = true},
                0o444
            );
        }
        defer std.posix.close(dir_fd);
        const mod_fd = try std.posix.openat(
            dir_fd,
            line,
            std.os.linux.O{.ACCMODE = .RDONLY},
            0o444
        );
        defer std.posix.close(mod_fd);
        _ = std.os.linux.syscall1(std.os.linux.syscalls.X86.finit_module, @intCast(mod_fd));
    }
}

pub export fn main() noreturn {
    load_modules() catch {};
    _ = std.os.linux.mount("procfs", "/proc", "procfs", 0, 0);
    // run_test();
    for (0..1) |idx| {
        var buff: [10]u8 = undefined;
        const tty_path = std.fmt.bufPrint(
            buff[0..10],
            "/dev/tty{d}",
            .{idx}
        ) catch {
            continue ;
        };
        const pid = std.posix.fork() catch {
            continue ;
        };
        if (pid == 0) {
            const tty = std.posix.open(
                if (idx > 0) tty_path else "/dev/tty",
                std.os.linux.O{ .ACCMODE = .RDWR },
                0o666
            ) catch 0;
            std.posix.dup2(@intCast(tty), 0) catch |err| {
                serial("dup2 error {d} -> 0 {t}\n", .{tty, err});
            };
            std.posix.dup2(@intCast(tty), 1) catch |err| {
                serial("dup2 error {d} -> 1 {t}\n", .{tty, err});
            };
            std.posix.dup2(@intCast(tty), 2) catch |err| {
                serial("dup2 error {d} -> 2 {t}\n", .{tty, err});
            };
            // run_test();
            var sh = shell.Shell.init();
            sh.start();
        }
    }
    while (true) {
        _ = std.posix.wait4(-1, 0, null);
    }
}
