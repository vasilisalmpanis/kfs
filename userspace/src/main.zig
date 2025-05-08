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
    const pid = std.posix.fork() catch |err| {
        serial("fork error {any}\n", .{err});
        return;
    };
    if (pid == 0) {
        // Following is failing with page fault and requires debugging
        // serial("I'm a child with pid {any}\n", .{
        //     os.linux.getpid()
        // });
        std.posix.exit(1);
    } else {
        serial("waitpid {any} result: {any}\n", .{
            pid,
            std.posix.waitpid(pid, 0)
        });
    }
}

var idx: u32 = 0;

fn kill_handler(sig: i32) callconv(.c) void {
    screen("testing {d} to screen\n", .{sig});
    serial("raising signal\n", .{});
    idx += 1;
    if (idx < 3) {
        _ = os.linux.kill(0, 1);
        serial("raised signal\n", .{});
    }
    serial("exiting handler\n", .{});
}

fn empty_func(_: i32) callconv(.c) void {
    serial("empty func\n", .{});
}

pub export fn main() linksection(".text.main") noreturn {
    test_wait();
    var status: u32 = undefined;
    const pid= os.linux.fork();
    if (pid == 0) {
        _ = os.linux.syscall0(os.linux.syscalls.X86.getpid); // FIXME
        // serial("child", .{});
        // while (true) {}
        os.linux.exit(5);
    } else {
        _ = os.linux.kill(@intCast(pid), 1);
        _ = os.linux.waitpid(@intCast(pid), &status, 0);
        _ = os.linux.write(1, "hello from userspace\n", 21);
        _ = os.linux.syscall6(os.linux.syscalls.X86.mmap2, 1, 2, 3, 4, 5, 6);
        std.log.info("test userspace logger {d}\n", .{5});
        _ = std.posix.kill(10, 4) catch null;
        _ = std.posix.write(2, "testing posix write\n") catch null;
        screen("testing {d} to screen\n", .{5});
        serial("testing {d} to serial\n", .{5});
        serial("waitpid 10: {any}\n", .{
            std.posix.waitpid(10, 0)
        });
        var action: std.posix.Sigaction = .{
            .handler = .{ .handler = &kill_handler },
            .mask = .{0} ** 32,
            .flags = os.linux.SA.SIGINFO | os.linux.SA.RESTORER | os.linux.SA.NODEFER,
        };
        idx = 0;
        _ = os.linux.sigaction(1, &action, null);
        // action.handler.handler = &empty_func;
        // _ = os.linux.sigaction(2, &action, null);
        serial("before kill", .{});
        _ = os.linux.kill(0, 1);
        serial("after kill", .{});
    }
    while (true) {}
}
