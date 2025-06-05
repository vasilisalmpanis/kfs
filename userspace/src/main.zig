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

fn test_wait() void {
    serial("waitpid  first {d}\n", .{1234});
    const pid = std.posix.fork() catch |err| {
        serial("fork error {any}\n", .{err});
        return;
    };
    serial("waitpid  first {d}\n", .{pid});
    if (pid == 0) {
        std.posix.exit(1);
    } else {
        serial("waitpid {any} result: {any}\n", .{
            pid,
            std.posix.waitpid(pid, 0)
        });
    }
}

fn custom_handler(_: i32) callconv(.c) void {
    serial("Custom handler for child process\n", .{});
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

fn allocate_memory() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const ptr = allocator.create(i32) catch null;
    ptr.?.* = 77;
    std.debug.print("Child process mapped memory: ptr={*} {d}\n", .{ptr, ptr.?.*});
}

fn IPC(fds: [2]i32) void {
    var message: [10]u8 = .{0} ** 10;
    var ret = os.linux.recvfrom(fds[1], @ptrCast(&message), 10, 0, null, null);
    while (ret == 0) {
        ret = os.linux.recvfrom(fds[1], @ptrCast(&message), 10, 0, null, null);
    }
    serial("received: {s}\n", .{message[0..10]});
}

fn PID_UID(task: [] const u8) void {
    const uid: u32 = os.linux.getuid();  
    const pid: i32 = os.linux.getpid();  
    serial("{s} UID: {d} PID: {d}", .{task, uid, pid});
}

fn setAction() void {
    const action: std.posix.Sigaction = .{
        .handler = .{ .handler = &custom_handler },
        .mask = .{@as(u32,1) << std.c.SIG.TRAP - 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        .flags = 0,
    };
    _ = os.linux.sigaction(std.c.SIG.ABRT, &action, null);
}

fn child_process(fds: [2]i32) void {
    test_wait();
    setAction();
    IPC(fds);
    PID_UID("Child");
    allocate_memory();

    // Child Process dies.
    os.linux.exit(5); 
}

pub export fn main() linksection(".text.main") noreturn {
    var fds: [2]i32 = .{0, 0};
    _ = os.linux.socketpair(os.linux.AF.UNIX, os.linux.SOCK.STREAM, 0, &fds);
    const pid= os.linux.fork();
    if (pid == 0) {
        child_process(fds);
    } else { 
        // Parent

        // IPC in parent
        const res = std.posix.sendto(fds[0], "test send", 0, null, 0) catch |err| brk: {
            serial("error: {any}", .{err});
            break :brk 0;
        };
        serial("Parent sent {d} bytes to child process\n", .{res});

        // PID / UID
        serial("PID of new Child {d}\n", .{pid});
        PID_UID("Parent");

        // Signaling
        _ = os.linux.kill(@intCast(pid), os.linux.SIG.ABRT);

        // waiting.
        var status: u32 = 0;
        _ = os.linux.wait4(@intCast(pid), &status, 0, null);
        serial("Child process exited with status: {d}\n", .{status});
    }
    while (true) {}
}
