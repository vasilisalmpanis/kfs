const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn read(fd: u32, buf: u32, size: u32) !u32 {
    const data: [*]u8 = @ptrFromInt(buf);
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.inode.mode.isDir()) {
            return errors.EISDIR;
        }
        if (!file.canRead())
            return errors.EACCES;
        return try file.ops.read(file, data, size);
    }
    return errors.EBADF;
}

pub fn pread(fd: u32, buf: [*]u8, size: u32, offset: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.inode.mode.isDir()) {
            return errors.EISDIR;
        }
        if (!file.canRead())
            return errors.EACCES;
        if (offset > file.inode.size)
            return 0;

        const old_offset = file.pos;
        defer file.pos = old_offset;

        file.pos = offset;
        return try file.ops.read(file, buf, size);
    }
    return errors.EBADF;
}

pub const IoVec = extern struct {
    base: [*]u8,
    len: usize,
};

pub fn readv(fd: u32, iov: [*]IoVec, iovcnt: u32) !u32 {
    var ret: u32 = 0;
    for (0..iovcnt) |idx| {
        const curr = iov[idx];
        if (curr.len > 0)
            ret += try read(
                fd,
                @intFromPtr(curr.base),
                curr.len
            );
    }
    return ret;
}

pub fn preadv(fd: u32, iov: [*]IoVec, iovcnt: u32, offset: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        const old_pos = file.pos;
        file.pos = offset;
        defer file.pos = old_pos;
        return try readv(fd, iov, iovcnt);
    }
    return errors.EBADF;
}
