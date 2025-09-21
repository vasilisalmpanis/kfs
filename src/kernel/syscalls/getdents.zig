const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");

pub fn getdents(_: u32, _: [*]u8, _: u32) !u32 {
    return errors.EFAULT;
}

pub fn getdents64(fd: u32, dirents: [*]u8, size: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |dir_file| {
        if (dir_file.inode.mode.isDir()) {
            if (dir_file.ops.readdir) |readdir| {
                const buf_slice = dirents[0..size];
                return try readdir(dir_file, buf_slice);
            }
            return errors.ENOENT;
        }
        return errors.ENOTDIR;
    }
    return errors.EBADF;
}
