const std = @import("std");
const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const krn = @import("../main.zig");

pub fn pipe(pipefd: ?*[2]i32) !u32 {
    return try pipe2(pipefd, 0);
}

pub fn pipe2(pipefd: ?*[2]i32, flags: i32) !u32 {
    const fds = pipefd
        orelse return errors.EFAULT;
    if ((flags & ~(
        @as(i32, @intCast(fs.file.O_CLOEXEC))
        | @as(i32, @intCast(fs.file.O_NONBLOCK)))) != 0
    )
        return errors.EINVAL;
    var write_file: *krn.fs.File = undefined;
    var read_file: *krn.fs.File = undefined;
    const read_fd: u32 = try krn.task.current.files.getNextFD();
    const write_fd: u32 = try krn.task.current.files.getNextFD();
    errdefer _ = krn.task.current.files.releaseFD(read_fd);
    errdefer _ = krn.task.current.files.releaseFD(write_fd);
    if (krn.fs.pipe.Pipe.newPipe()) |pipe_data| {
        errdefer krn.mm.kfree(pipe_data);
        const pipe_inode = try krn.fs.Inode.allocEmpty();
        errdefer krn.mm.kfree(pipe_inode);
        pipe_inode.fops = &krn.fs.pipe.PipeFileOps;
        pipe_inode.ref.ref();
        pipe_inode.mode = fs.UMode.fifo();
        pipe_inode.data.pipe = pipe_data;
        
        write_file = try krn.fs.File.pseudo(pipe_inode);
        errdefer write_file.ref.unref();
        write_file.mode = fs.UMode.fifo();
        write_file.flags = fs.file.O_WRONLY | @as(u32, @intCast(flags));

        read_file = try krn.fs.File.pseudo(pipe_inode);
        errdefer read_file.ref.unref();
        read_file.mode = fs.UMode.fifo();
        read_file.flags = fs.file.O_RDONLY | @as(u32, @intCast(flags));

        try krn.task.current.files.setFD(read_fd, read_file);
        try krn.task.current.files.setFD(write_fd, write_file);
        krn.logger.INFO("pipe: write file refcount: {d}", .{write_file.ref.count.raw});
        fds[0] = @intCast(read_fd);
        fds[1] = @intCast(write_fd);
    } else {
        return errors.ENOMEM;
    }
    return 0;
}
