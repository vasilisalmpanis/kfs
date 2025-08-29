const os = @import("std").os;
const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");

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
    _ = std.io.getStdErr().writer().print(format, args) catch null;
}

fn screen(comptime format: []const u8, args: anytype) void {
    _ = std.io.getStdOut().writer().print(format, args) catch null;
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
    std.posix.exit(55);
}

// var idx: u32 = 0;
// fn siginfo_hand(a: i32, b: *const os.linux.siginfo_t, c: ?*anyopaque) callconv(.c) void {
//     const ucontext: ?*os.linux.ucontext_t = @ptrCast(@alignCast(c));
//     serial("siginfo args: {d} {any} {any}\n", .{a, b, ucontext});
//     serial("raising signal\n", .{});
//     idx += 1;
//     if (idx < 3) {
//         _ = os.linux.kill(0, 1);
//         serial("raised signal\n", .{});
//     }
//     serial("exiting handler\n", .{});
// }

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
        .mask = .{@as(u32,1) << std.c.SIG.TRAP - 1} ++ .{0} ** 31,
        .flags = 0,
    };
    _ = os.linux.sigaction(std.c.SIG.ABRT, &action, null);
}

fn childProcess(sock_fd: i32) void {
    testWait();
    pidUid("[CHILD]");
    setAction();
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

pub export fn main() linksection(".text.main") noreturn {
    var fds: [2]i32 = .{0, 0};
    _ = os.linux.socketpair(
        os.linux.AF.UNIX,
        os.linux.SOCK.STREAM,
        0,
        &fds
    );
    var fd = std.os.linux.open("lol", .{ .CREAT = true }, 0o444);
    fd = std.os.linux.open("lol2", .{ .CREAT = true }, 0o444);
    const wl = std.posix.write(@intCast(fd), "testing write and read") catch 0;
    serial("result of writing to {d}:\n  len:{d}\n", .{fd, wl});
    _ = std.posix.lseek_SET(@intCast(fd), 0) catch null;
    const pid= os.linux.fork();
    if (pid == 0) {
        _ = std.posix.lseek_SET(@intCast(fd), 0) catch null;
        var buf1: [30]u8 = .{0} ** 30;
        const rl = std.posix.read(@intCast(fd), &buf1) catch 1;
        serial("\n\n\nChild process read:\n  len:{d}\n  data: {s}\n\n\n", .{rl, buf1[0..rl]});
        childProcess(fds[1]);
    } else { 
        // Parent
        // PID / UID
        serial("[PARENT] PID of new Child {d}\n", .{pid});
        pidUid("[PARENT]");

        // IPC in parent
        const res = std.posix.sendto(
            fds[0],
            "test send",
            0,
            null,
            0
        ) catch |err| brk: {
            serial("[PARENT] error: {any}", .{err});
            break :brk 0;
        };
        serial("[PARENT] Parent sent {d} bytes to child process\n", .{res});
        

        // // Waiting for child to send message
        var buf: [30]u8 = .{0} ** 30;
        while (
            std.posix.recvfrom(
                fds[0],
                @ptrCast(&buf),
                0,
                null,
                null
            ) catch 0 == 0
        ) {}

        fd = std.os.linux.open("lol", .{ .CREAT = true }, 0o444);
        serial("new fd {any}\n", .{fd});
        fd = std.os.linux.open("lol2", .{ .CREAT = true }, 0o444);
        serial("new fd {any}\n", .{fd});
        fd = std.os.linux.open("lol3", .{ .CREAT = true }, 0o444);
        serial("new fd {any}\n", .{fd});
        const _wl = std.posix.write(@intCast(fd), "testing write and read") catch 0;
        serial("result of writing:\n  len:{d}\n", .{_wl});
        _ = std.posix.lseek_SET(@intCast(fd), 0) catch null;
        serial("after lseek\n",.{});
        var rl = std.posix.read(@intCast(fd), &buf) catch 1;
        serial("result of reading:\n  len:{d}\n  data: {s}\n", .{rl, buf[0..rl]});
        serial("new fd {any}\n", .{fd});
        fd = std.os.linux.open("lol3", .{ .CREAT = true }, 0o444);
        _ = std.posix.close(3);
        _ = std.posix.close(4);
        _ = std.posix.close(5);
        _ = std.posix.close(6);
        _ = std.posix.close(7);
        _ = std.posix.lseek_SET(@intCast(8), 0) catch null;
        rl = std.posix.read(@intCast(8), &buf) catch 1;
        fd = std.os.linux.open("/dev/8250", .{ .CREAT = true }, 0o444);
        serial("new fd for dev {any}\n", .{fd});
        _ = std.posix.write(@intCast(fd), "We can now print to serial from userspace\n") catch 0;
        serial("result of reading:\n  len:{d}\n  data: {s}\n", .{rl, buf[0..rl]});
        _ = std.posix.close(8);
        fd = std.os.linux.open("/dev/sda", .{ .CREAT = true }, 0o444);

        // var big_buf: [512]u8 = .{0} ** 512;
        // for (0..5000) |_| {
        //     const r = std.posix.read(@intCast(fd), &big_buf) catch 0;
        //     if (!std.mem.allEqual(u8, &big_buf, 0)) {
        //         serial("result of reading:\n{s}\n", .{big_buf[0..r]});
        //     }
        // }

        // Signaling
        serial("[PARENT] sending signal {any} to child\n", .{os.linux.SIG.ABRT});
        _ = os.linux.kill(@intCast(pid), os.linux.SIG.ABRT);
        // waiting.
        var status: u32 = 0;
        _ = os.linux.wait4(@intCast(pid), &status, 0, null);
        serial("[PARENT] Child process exited with status: {d}\n", .{status});
    }
    while (true) {}
}
