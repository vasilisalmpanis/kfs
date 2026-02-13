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
        krn.mm.kfreeSlice(slice[idx]);
    }
    krn.mm.kfreeSlice(slice);
}

const FormatType = enum(u8) {
    ELF,
    Shbang,
    Unknown,
};

fn getFileType(file: []const u8) FormatType{
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

    return .Unknown;
}

fn handlerShbang(
    binary: []u8,
    argv: []const []const u8,
    envp: []const []const u8,
    free_arg_env: bool,
    file: *krn.fs.File,
) anyerror!u32 {
    const new_line_idx = std.mem.indexOf(u8, binary, "\n") orelse binary.len;
    const shebang_line = binary[2..new_line_idx];
    const trimmed_shebang_line = std.mem.trim(u8, shebang_line, "\t\r");
    if (trimmed_shebang_line.len == 0) {
        return errors.ENOEXEC;
    }

    const space_idx = std.mem.indexOfAny(u8, shebang_line, " \t");
    const interp_raw = if (space_idx) |idx| shebang_line[0..idx] else shebang_line;
    const interp_arg = if (space_idx) |idx| std.mem.trim(u8, shebang_line[idx + 1 ..], "\t\r") else null;

    const interp = dupString(interp_raw) orelse return errors.ENOMEM;
    errdefer krn.mm.kfreeSlice(interp);

    const extra_args: usize = if (interp_arg != null and interp_arg.?.len > 0) 2 else 1;
    const new_argv = krn.mm.kmallocSlice([]const u8, argv.len + extra_args) orelse
        return errors.ENOMEM;
    errdefer krn.mm.kfreeSlice(new_argv);

    var arg_idx: usize = 0;

    new_argv[arg_idx] = interp;
    arg_idx += 1;

    if (interp_arg != null and interp_arg.?.len > 0) {
        const arg_copy = dupString(interp_arg.?) orelse return errors.ENOMEM;
        new_argv[arg_idx] = arg_copy;
        arg_idx += 1;
    }

    for (argv) |arg| {
        new_argv[arg_idx] = arg;
        arg_idx += 1;
    }

    krn.mm.kfreeSlice(binary);
    file.ref.unref();

    if (free_arg_env) {
        krn.mm.kfreeSlice(argv);
        // envp is passed through, recursive call will free it
    }

    return doExecve(
        interp,
        new_argv,
        envp,
        true
    );
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
    errdefer krn.mm.kfreeSlice(slice);

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
            if (free_arg_env)
                krn.mm.kfreeSlice(filename);
            return try handlerShbang(
                slice,
                argv,
                envp,
                free_arg_env,
                file
            );
        },
        .Unknown => return errors.ENOEXEC,
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

    // Release the file's content buffer since
    // its already copied to the new tasks mappings.
    // By unrefing the file we also release the path
    krn.mm.kfreeSlice(slice);
    if (free_arg_env)
        krn.mm.kfreeSlice(filename);
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

fn dupString(src: []const u8) ?[]u8 {
    const dst = krn.mm.kmallocSlice(u8, src.len) orelse return null;
    @memcpy(dst, src);
    return dst;
}


pub fn dupStrings(array: [*:null]?[*:0]u8) ![][]u8 {
    var len: u32 = 0;
    while (array[len] != null) {
        len += 1;
    }
    const slice = if (krn.mm.kmallocSlice([]u8, len)) |s| s
        else return errors.ENOMEM;
    errdefer krn.mm.kfreeSlice(slice);

    for (0..len) |idx| {
        const s_span = std.mem.span(array[idx].?);
        const string = dupString(s_span) orelse {
            for (0..idx) |i| {
                krn.mm.kfreeSlice(slice[i]);
            }
            return errors.ENOMEM;
        };
        slice[idx] = string;
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

    const user_filename = std.mem.span(filename.?);
    const filename_copy = dupString(user_filename) orelse return errors.ENOMEM;
    errdefer krn.mm.kfreeSlice(filename_copy);

    // New argv
    const argv_slice = try dupStrings(argv);
    errdefer freeSlices(argv_slice, argv_slice.len);

    // New envp
    const envp_slice = try dupStrings(envp);
    errdefer freeSlices(envp_slice, envp_slice.len);

    const result = doExecve(
        filename_copy,
        argv_slice,
        envp_slice,
        true,
    );

    krn.mm.kfreeSlice(filename_copy);
    return result;
}
