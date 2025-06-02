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
    serial("SIGUSR1\n", .{});
    // while (true) {}
}

fn empty_func2(_: i32) callconv(.c) void {
    serial("SIGUSR2\n", .{});
    // while (true) {}
}

fn siginfo_hand(a: i32, b: *const os.linux.siginfo_t, c: ?*anyopaque) callconv(.c) void {
    const ucontext: ?*os.linux.ucontext_t = @ptrCast(@alignCast(c));
    serial("siginfo args: {d} {any} {any}\n", .{a, b, ucontext});
    serial("raising signal\n", .{});
    idx += 1;
    if (idx < 3) {
        _ = os.linux.kill(0, 1);
        serial("raised signal\n", .{});
    }
    serial("exiting handler\n", .{});
}

pub export fn main() linksection(".text.main") noreturn {
    // test_wait();
    // var status: u32 = undefined;
    var fds: [2]i32 = .{0, 0};
    _ = os.linux.socketpair(os.linux.AF.UNIX, os.linux.SOCK.STREAM, 0, &fds);
    const pid= os.linux.fork();
    if (pid == 0) {
        var i: u32 = 0;
        while (i < 1000000) {
            i += 1;
        }
        var action: std.posix.Sigaction = .{
            .handler = .{ .handler = &empty_func },
            .mask = .{@as(u32,1) << std.c.SIG.TRAP - 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
            // .mask = {@bitCast(std.c.SIG.TRAP)},
            .flags = os.linux.SA.RESTORER,// | os.linux.SA.NODEFER,
        };
        action.mask[std.c.SIG.TRAP] = 1;
        _ = os.linux.sigaction(std.c.SIG.USR1, &action, null);
        action.handler.handler = &empty_func2;
        action.mask[std.c.SIG.TRAP] = 0;
        var action2: std.posix.Sigaction = .{
            .handler = .{ .handler = &empty_func2 },
            .mask = .{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
            // .mask = {@bitCast(std.c.SIG.TRAP)},
            .flags = os.linux.SA.RESTORER,// | os.linux.SA.NODEFER,
        };
        _ = os.linux.sigaction(std.c.SIG.USR2, &action2, null);
        _ = os.linux.kill(3, std.c.SIG.USR1);
        _ = os.linux.syscall0(os.linux.syscalls.X86.sigpending); // FIXME
        // serial("child after {d}\n", .{ret});
        var buf: [10]u8 = .{0} ** 10;
        // @memcpy(buf[0..10], "1234567890");
        var ret = os.linux.recvfrom(fds[1], @ptrCast(&buf), 10, 0, null, null);
        while (ret == 0) {
            ret = os.linux.recvfrom(fds[1], @ptrCast(&buf), 10, 0, null, null);
        }
        serial("received: {s}\n", .{buf[0..10]});
        os.linux.exit(5);
    } else {
        const res = std.posix.sendto(fds[0], "test send", 0, null, 0) catch |err| brk: {
            serial("error: {any}", .{err});
            break :brk 0;
        };
        var num: usize = os.linux.mmap(@ptrFromInt(0xb0000), 4096, os.linux.PROT.WRITE, .{.ANONYMOUS = true, .TYPE = os.linux.MAP_TYPE.PRIVATE}, -1, 0);
        serial("allocated mem {x}\n", .{num});
        num = os.linux.mmap(@ptrFromInt(0xb0000), 4096, os.linux.PROT.WRITE, .{.ANONYMOUS = true, .TYPE = os.linux.MAP_TYPE.PRIVATE}, -1, 0);
        serial("allocated mem {x}\n", .{num});
        num = os.linux.mmap(@ptrFromInt(0xc0000), 4096, os.linux.PROT.WRITE, .{.ANONYMOUS = true, .TYPE = os.linux.MAP_TYPE.PRIVATE}, -1, 0);
        serial("allocated mem {x}\n", .{num});
        num = os.linux.mmap(@ptrFromInt(0xbe000), 2 * 4096, os.linux.PROT.WRITE, .{.ANONYMOUS = true, .TYPE = os.linux.MAP_TYPE.PRIVATE}, -1, 0);
        serial("allocated mem {x}\n", .{num});
        num = os.linux.mmap(@ptrFromInt(0xa7000), 2 * 4096, os.linux.PROT.WRITE, .{.ANONYMOUS = true, .TYPE = os.linux.MAP_TYPE.PRIVATE}, -1, 0);
        serial("allocated mem {x}\n", .{num});
        // serial("num {x}\n", .{num});

        var status: u32 = 0;
        _ = os.linux.wait4(@intCast(pid), &status, 0, null);
        // const res = os.linux.sendto(fds[0], "test send", 10, 0, null, 0);
        // var i: u32 = 0;
        // while (i < 1000000000) {
        //     i += 1;
        // }
        // _ = os.linux.kill(0, 2);
        serial("parent after {d}\n", .{res});
    }
    //     _ = os.linux.kill(@intCast(pid), 1);
    //     _ = os.linux.waitpid(@intCast(pid), &status, 0);
    //     _ = os.linux.write(1, "hello from userspace\n", 21);
    //     _ = os.linux.syscall6(os.linux.syscalls.X86.mmap2, 1, 2, 3, 4, 5, 6);
    //     std.log.info("test userspace logger {d}\n", .{5});
    //     _ = std.posix.kill(10, 4) catch null;
    //     _ = std.posix.write(2, "testing posix write\n") catch null;
    //     screen("testing {d} to screen\n", .{5});
    //     serial("testing {d} to serial\n", .{5});
    //     serial("waitpid 10: {any}\n", .{
    //         std.posix.waitpid(10, 0)
    //     });
    // var action: std.posix.Sigaction = .{
    //     // .handler = .{ .sigaction = &siginfo_hand },
    //     .handler = .{ .handler = &kill_handler },
    //     .mask = .{0} ** 32,
    //     .flags = os.linux.SA.SIGINFO | os.linux.SA.RESTORER | os.linux.SA.NODEFER,
    // };
    // idx = 0;
    // _ = os.linux.sigaction(1, &action, null);
    // // action.handler.handler = &empty_func;
    // // _ = os.linux.sigaction(2, &action, null);
    // serial("before kill", .{});
    // _ = os.linux.kill(0, 1);
    // serial("after kill", .{});
    // }
    while (true) {}
}
