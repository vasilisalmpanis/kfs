const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");
// Manual translation for LP64 (e.g. x86_64 Linux).
// Use `extern` so the layout/ABI matches C when linking with C code.
pub const Timespec = extern struct {
    tv_sec: u32,   // time_t -> signed 64-bit on LP64
    tv_nsec: u32,  // long -> signed 64-bit
                   //
    fn init() Timespec {
        return Timespec{
            .tv_sec = 0,
            .tv_nsec = 0,
        };
    }
};

pub const Stat = extern struct {
    st_dev: u64,         // dev_t
    __padding: u32,      // padding
    _st_ino: u32,        // ino_t
    st_mode: u32,        // mode_t (often 32-bit)
    st_nlink: u32,       // nlink_t
    st_uid: u32,         // uid_t (32-bit)
    st_gid: u32,         // gid_t (32-bit)
    st_rdev: u64,        // dev_t (special device)
    __pad0: u32,         // unsigned int __pad0
    st_size: i64,        // off_t
    st_blksize: u32,     // blksize_t (signed long)
    st_blocks: u64,      // blkcnt_t (signed long)
    st_atim: Timespec,   // struct timespec
    st_mtim: Timespec,   // struct timespec
    st_ctim: Timespec,   // struct timespec
    st_ino: u64,
};

pub fn do_stat64(inode: *fs.Inode, buf: *Stat) !void {
    const sb = if (inode.sb) |_s| _s else return krn.errors.PosixError.EINVAL;
    buf.st_dev = 0;
    if (sb.dev_file) |blkdev| {
        const dev: u16 = @bitCast(blkdev.inode.dev_id);
        buf.st_dev = @intCast(dev);
    }
    buf._st_ino = inode.i_no;
    buf.st_ino = inode.i_no;
    buf.st_nlink = 0; // No hard links yet.
    const mode: u16 = @bitCast(inode.mode);
    buf.__padding = 0;
    buf.__pad0 = 0;
    buf.st_mode = @intCast(mode);
    buf.st_uid = @intCast(inode.uid);
    buf.st_gid = @intCast(inode.gid);
    const dev: u16 = @bitCast(inode.dev_id);
    buf.st_rdev = @intCast(dev);
    buf.st_size = inode.size;
    buf.st_blksize = sb.block_size;
    buf.st_blocks = 0;

    buf.st_atim = Timespec.init();
    buf.st_mtim = Timespec.init();
    buf.st_ctim = Timespec.init();
}

pub fn stat64(path: ?[*:0]u8, buf: ?*Stat) !u32 {
    if (path == null or buf == null) return errors.EFAULT;

    const path_slice = std.mem.span(path.?);
    const stat_buf: *Stat = buf.?;
    const inode_path: fs.path.Path = try fs.path.resolve(path_slice);
    const inode: *fs.Inode = inode_path.dentry.inode;

    try do_stat64(inode, stat_buf);
    return 0;
}

pub fn fstat64(fd: u32, buf: ?*Stat) !u32 {
    if (buf == null) {
        return errors.EFAULT;
    } 
    if (krn.task.current.files.fds.get(fd)) |file| {
        try do_stat64(file.inode, buf.?);
        return 0;
    }
    return errors.EBADF;
}

pub fn fstatat64(
    dir_fd: u32,
    path: ?[*:0]u8,
    buf: ?*Stat,
    flags: u32
) !u32 {
    _ = flags;
    if (buf == null) {
        return errors.EFAULT;
    }
    if (path == null) {
        return errors.ENOENT;
    }
    const path_slice = std.mem.span(path.?);
    if (path_slice.len == 0) {
        return errors.ENOENT;
    }
    if (path_slice[0] == '/') {
        return stat64(path, buf);
    } else if (krn.task.current.files.fds.get(dir_fd)) |file| {
        if (!file.inode.mode.isDir()) {
            return errors.ENOTDIR;
        }
        if (file.path == null)
            return errors.ENOENT;
        const from_path = file.path.?.clone();
        defer from_path.release();
        const target = try fs.path.resolveFrom(path_slice, from_path);
        defer target.release();
        try do_stat64(target.dentry.inode, buf.?);
        return 0;
    } 
    return errors.EBADF;
}
