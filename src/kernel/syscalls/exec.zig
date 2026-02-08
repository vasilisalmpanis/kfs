const krn = @import("../main.zig");
const doFork = @import("../sched/process.zig").doFork;
const arch = @import("arch");
const errors = @import("error-codes.zig").PosixError;
const std = @import("std");

// Flags for execveat2(2). //
const AT_EXECVE_CHECK		        = 0x10000; // Only perform a check if execution


pub fn freeSlices(
    slice: []const []const u8,
    len: usize
) void {
    for (0..len) |idx| {
        krn.mm.kfree(slice[idx].ptr);
    }
    krn.mm.kfree(@ptrCast(slice.ptr));
}

const FormatType = enum(u8) {
    ELF,
    Shbang,
    Unkown,
    Empty,
};

fn getFileType(file: []const u8) FormatType{
    if (file.len == 0) {
        return .Empty;
    }

    if (file.len >= 4 and
        file[0] == 0x7f and
        file[1] == 'E' and
        file[2] == 'L' and
        file[3] == 'F')
    {
        return .ELF;
    }

    if (file.len >= 2 and file[0] == '#' and file[1] == '!') {
        return .Shbang;
    }

    return .Unkown;
}

pub fn doExecve(
    filename: []const u8,
    argv: []const []const u8,
    envp: []const []const u8,
    free_arg_env: bool,
) !u32 {
    // TODO:
    // - check suid / sgid and change euid / egid if needed
    const path = try krn.fs.path.resolve(filename);
    errdefer path.release();
    const inode = path.dentry.inode;
    if (!inode.mode.canExecute(inode.uid, inode.gid) or !inode.mode.isReg()) {
        return errors.EACCES;
    }
    const file = try krn.fs.File.new(path);
    errdefer file.ref.unref();
    const slice = if (krn.mm.kmallocSlice(u8, file.inode.size)) |_slice|
        _slice
    else
        return errors.ENOMEM;
    var read: usize = 0;
    krn.logger.INFO("Executing {s} {d}\n", .{filename, file.inode.size});
    while (read < file.inode.size) {
        read += try file.ops.read(file, @ptrCast(&slice[read]), slice.len);
    }

    switch (getFileType(slice)) {
        .ELF => {
            krn.userspace.validateElfHeader(slice) catch |err| {
                krn.logger.ERROR("ELF validation failed: {}\n", .{err});
                return errors.ENOEXEC;
            };
        },
        .Shbang => {
        },
        .Unkown,
        .Empty => return errors.ENOEXEC,
    }

    krn.task.current.setName(path.dentry.name); // TODO: make copy of filename and set name only if we will execute

    if (krn.task.current.mm) |_mm| {
        _mm.releaseMappings();
    }

    try krn.userspace.prepareBinary(
        slice,
        argv,
        envp,
    );

    // Release the file content buffer since
    // its already copied to the new tasks mappings.
    // By unrefing the file we also release the path
    krn.mm.kfree(slice.ptr);
    file.ref.unref();

    if (free_arg_env) {
        freeSlices(argv, argv.len);
        freeSlices(envp, envp.len);
    }

    krn.task.current.sighand = krn.signals.SigHand.init();
    var it = krn.task.current.files.closexec.iterator(
        .{.direction = .forward, .kind = .set}
    );
    while (it.next()) |_fd| {
        _ = krn.task.current.files.releaseFD(_fd);
    }

    krn.task.current.fpu_used = false;
    krn.task.current.save_fpu_state = false;
    arch.fpu.setTaskSwitched();

    krn.userspace.goUserspace();
    return 0;
}

pub fn dupStrings(array: [*:null]?[*:0]u8) ![][]u8 {
    var len: u32 = 0;
    while (array[len] != null) {
        len += 1;
    }
    const slice = if (krn.mm.kmallocSlice([]u8, len)) |s| s
        else return errors.ENOMEM;
    for (0..len) |idx| {
        const s_span = std.mem.span(array[idx].?);
        if (krn.mm.kmallocArray(u8, s_span.len)) |string| {
            @memcpy(string[0..s_span.len], s_span);
            slice[idx] = string[0..s_span.len];
        } else {
            if (idx - 1 >= 0)
                freeSlices(slice, idx - 1);
            return errors.ENOMEM;
        }
    }
    return slice;
}

pub fn execve(
    filename: ?[*:0]const u8,
    u_argv: ?[*:null]?[*:0]u8,
    u_envp: ?[*:null]?[*:0]u8,
) !u32 {
    if (filename == null or u_argv == null or u_envp == null)
        return errors.EFAULT;
    const argv: [*:null]?[*:0]u8 = u_argv.?;
    const envp: [*:null]?[*:0]u8 = u_envp.?;
    const span = std.mem.span(filename.?);

    // New argv
    const argv_slice = try dupStrings(argv);
    errdefer freeSlices(argv_slice, argv_slice.len);

    // New envp
    const envp_slice = try dupStrings(envp);
    errdefer freeSlices(envp_slice, envp_slice.len);

    return try doExecve(
        span,
        argv_slice,
        envp_slice,
        true,
    );
}
