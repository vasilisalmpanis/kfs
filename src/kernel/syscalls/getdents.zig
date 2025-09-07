const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");

pub const DT_UNKNOWN	= 0;
pub const DT_FIFO		= 1;
pub const DT_CHR		= 2;
pub const DT_DIR		= 4;
pub const DT_BLK		= 6;
pub const DT_REG		= 8;
pub const DT_LNK		= 10;
pub const DT_SOCK		= 12;
pub const DT_WHT		= 14;


pub const Dirent = extern struct {
    ino: u32,
    off: u32,
    reclen: u16,
    name: [256]u8,
};

pub const Dirent64 = extern struct {
    ino: u64,
    off: u64,
    reclen: u16,
    type: u8,
    name: [256]u8,
};

pub fn getdents(_: u32, _: [*]u8, _: u32) !u32 {
    return errors.EFAULT;
}

pub fn getdents64(fd: u32, dirents: [*]u8, size: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |dir_file| {
        if (dir_file.ops.readdir) |readdir| {
            const buf_slice = dirents[0..size];
            return try readdir(dir_file, buf_slice);
        }
        return errors.ENOENT;
    }
    return errors.EFAULT;
}
