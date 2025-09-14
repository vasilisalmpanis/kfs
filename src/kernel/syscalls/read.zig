const errors = @import("./error-codes.zig");
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn read(fd: u32, buf: u32, size: u32) !u32 {
    const data: [*]u8 = @ptrFromInt(buf);
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.inode.mode.isDir()) {
            return errors.PosixError.EISDIR;
        }
        if (!file.canRead())
            return errors.PosixError.EACCES;
        return try file.ops.read(file, data, size);
    }
    return errors.PosixError.EBADF;
}

pub fn pread(fd: u32, buf: [*]u8, size: u32, offset: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.inode.mode.isDir()) {
            return errors.PosixError.EISDIR;
        }
        if (!file.canRead())
            return errors.PosixError.EACCES;
        if (offset > file.inode.size)
            return 0;

        const old_offset = file.pos;
        defer file.pos = old_offset;

        file.pos = offset;
        return try file.ops.read(file, buf, size);
    }
    return errors.PosixError.EBADF;
}
