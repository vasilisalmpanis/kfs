const os = @import("std").os;
const std = @import("std");

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
    _ = os.linux.write(1, data.ptr, data.len);
}

pub export fn main() linksection(".text.main") noreturn {
    var status: u32 = undefined;
    const pid= os.linux.fork();
    if (pid == 0) {
        _ = os.linux.syscall0(os.linux.syscalls.X86.getpid);
        os.linux.exit(5);
    } else {
        _ = os.linux.waitpid(@intCast(pid), &status, 0);
        _ = os.linux.kill(@intCast(pid), 1);
        _ = os.linux.write(1, "hello from userspace\n", 21);
        _ = os.linux.syscall6(os.linux.syscalls.X86.mmap2, 1, 2, 3, 4, 5, 6);
        std.log.info("test userspace logger {d}\n", .{5});
    }
    while (true) {}
}
