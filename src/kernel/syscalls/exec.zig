const krn = @import("../main.zig");
const doFork = @import("../sched/process.zig").doFork;
const arch = @import("arch");
const errors = @import("error-codes.zig").PosixError;
const std = @import("std");

pub fn doExecve(
    filename: []const u8,
    argv: []const []const u8,
    envp: []const []const u8,
) !u32 {
    // function body
    const path = try krn.fs.path.resolve(filename);
    errdefer path.release();
    const file = try krn.fs.File.new(path);
    errdefer file.ref.unref();
    if (krn.task.current.mm) |_mm| {
        _mm.releaseMappings();
    }
    const slice = if (krn.mm.kmallocSlice(u8, file.inode.size)) |_slice| _slice else return errors.ENOMEM;
    var read: u32 = 1;
    while (read < file.inode.size) {
        krn.logger.INFO("read {d} of {d}\n", .{read, file.inode.size});
        read += try file.ops.read(file, slice.ptr, slice.len);
    }
    krn.userspace.goUserspace(
        slice,
        argv,
        envp,
    );
    return 0;
}

pub fn execve(
    filename: ?[*:0]const u8,
) !u32 {
    if (filename == null)
        return errors.EINVAL;
    const span = std.mem.span(filename.?);
    return doExecve(
        span, 
        krn.userspace.argv_init,
        krn.userspace.envp_init,
    );
}
