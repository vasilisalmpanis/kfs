const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn write(fd: u32, buf: ?[*]u8, size: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        file.ref.ref();
        defer file.ref.unref();
        if (!file.canWrite())
            return errors.EACCES;
        if (size == 0)
            return 0;
        const data = buf orelse
            return errors.EFAULT;
        if (file.flags & krn.fs.file.O_APPEND != 0) {
            file.pos = file.inode.size;
        }
        return try file.ops.write(file, data, size);
    }
    krn.logger.INFO("Error {d}\n", .{krn.task.current.pid});
    return errors.EBADF;
}

pub const IoVec = extern struct {
    base: ?[*]u8,
    len: usize,
};

pub fn writev(fd: u32, iov: ?[*]IoVec, iovcnt: u32) !u32 {
    if (iovcnt == 0)
        return 0;
    const iovec = iov orelse
        return errors.EFAULT;
    var ret: u32 = 0;
    for (0..iovcnt) |idx| {
        const curr = iovec[idx];
        if (curr.len > 0) {
            const single_write: u32 = try write(fd, curr.base, curr.len);
            ret += single_write;
            if (single_write != curr.len) {
                return ret;
            }
        }
    }
    return ret;
}

pub fn pwritev(fd: u32, iov: ?[*]IoVec, iovcnt: u32, offset: u32) !u32 {
    _ = offset;
    return try writev(fd, iov, iovcnt);
}
