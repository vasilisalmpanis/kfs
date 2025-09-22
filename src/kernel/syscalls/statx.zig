const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");

const AT_FDCWD = -100;

const StatxTimestamp = extern struct{
	tv_sec: i64,
	tv_nsec: u32,
	__reserved: i32,

    pub fn initEmpty() StatxTimestamp {
        return StatxTimestamp{
            .tv_sec = 0,
            .tv_nsec = 0,
            .__reserved = 0,
        };
    }
};

const Statx = extern struct{
	stx_mask: u32,	            // What results were written [uncond]
	stx_blksize: u32,	        // Preferred general I/O size [uncond]
	stx_attributes: u64,	    // Flags conveying information about the file [uncond]
	stx_nlink: u32,	            // Number of hard links
	stx_uid: u32,	            // User ID of owner
	stx_gid: u32,	            // Group ID of owner
	stx_mode: u16,	            // File mode
	__spare0: u16,
	stx_ino: u64,               // Inode number
	stx_size: u64,              // File size
	stx_blocks: u64,            // Number of 512-byte blocks allocated
	stx_attributes_mask: u64,           // Mask to show what's supported in stx_attributes
    // File timestamps
	stx_atime: StatxTimestamp,	        // Last access time
	stx_btime: StatxTimestamp,	        // File creation time
	stx_ctime: StatxTimestamp,	        // Last attribute change time
	stx_mtime: StatxTimestamp,	        // Last data modification time
    // ID of the device of this inode
	stx_rdev_major: u32,                // Device ID of special file [if bdev/cdev]
	stx_rdev_minor: u32,
    // ID of device containing containing the filesystem of this inode
	stx_dev_major: u32,                 // ID of device containing file [uncond]
	stx_dev_minor: u32,
	stx_mnt_id: u64,
    // Direct I/O alignment restrictions
	stx_dio_mem_align: u32,             // Memory buffer alignment for direct I/O
	stx_dio_offset_align: u32,          // File offset alignment for direct I/O
	stx_subvol: u64,	                // Subvolume identifier
    // Direct I/O atomic write limits
	stx_atomic_write_unit_min: u32,	    // Min atomic write unit in bytes
	stx_atomic_write_unit_max: u32,	    // Max atomic write unit in bytes
	stx_atomic_write_segments_max: u32, // Max atomic write segment count
	__spare1: u32,
	__spare3: [9]u64,   	            // Spare space for future expansion
};

pub fn do_statx(inode: *fs.Inode, buf: *Statx) !u32 {
    const sb = if (inode.sb) |_s| _s
        else return krn.errors.PosixError.EINVAL;
    buf.stx_mask = 0;
    buf.stx_blksize = sb.block_size;
    buf.stx_attributes = 0;
    buf.stx_nlink = 0;
    buf.stx_uid = inode.uid;
    buf.stx_gid = inode.gid;
    buf.stx_mode = inode.mode.toU16();
    buf.__spare0 = 0;
    buf.stx_ino = inode.i_no;
    buf.stx_size = inode.size;
    buf.stx_blocks = 0;
    buf.stx_attributes_mask = 0;

    buf.stx_atime = StatxTimestamp.initEmpty();
    buf.stx_btime = StatxTimestamp.initEmpty();
    buf.stx_ctime = StatxTimestamp.initEmpty();
    buf.stx_mtime = StatxTimestamp.initEmpty();

    buf.stx_rdev_major = inode.dev_id.major;
    buf.stx_rdev_minor = inode.dev_id.minor;

    buf.stx_dev_major = 0;
    buf.stx_dev_minor = 0;
    if (sb.dev_file) |blkdev| {
        buf.stx_dev_major = @intCast(blkdev.inode.dev_id.major);
        buf.stx_dev_minor = @intCast(blkdev.inode.dev_id.minor);
    }

    buf.stx_mnt_id = 0;

    buf.stx_dio_mem_align = 0;
    buf.stx_dio_offset_align = 0;
    buf.stx_subvol = 0;

    buf.stx_atomic_write_unit_min = 0;
    buf.stx_atomic_write_unit_max = 0;
    buf.stx_atomic_write_segments_max = 0;

    buf.__spare1 = 0;
    buf.__spare3 = [_]u64{0} ** 9;
    return 0;
}

pub fn statx(dirfd: i32, path: ?[*:0]u8, flags: u32, mask: u32, statxbuf: ?*Statx) !u32 {
    if (path == null or statxbuf == null)
        return errors.EFAULT;
    const path_s: []const u8 = std.mem.span(path.?);
    if (dirfd != AT_FDCWD and dirfd < 0)
        return errors.EBADF;
    krn.logger.DEBUG(
        "statx {s} in {d} flags: {x}, mask: {x}, buf addr: {x}",
        .{path_s, dirfd, flags, mask, @intFromPtr(statxbuf)}
    );
    if (path_s.len == 0) {
        if (dirfd < 0) {
            return errors.EFAULT;
        }
        if (krn.task.current.files.fds.get(@intCast(dirfd))) |file| {
            return try do_statx(file.inode, statxbuf.?);
        }
        return errors.EBADF;
    }
    var from_path = krn.task.current.fs.pwd;
    if (path_s[0] != '/') {
        if (dirfd == AT_FDCWD) {
            const cwd = krn.task.current.fs.pwd.clone();
            defer cwd.release();
            return try do_statx(cwd.dentry.inode, statxbuf.?);
        } else if (krn.task.current.files.fds.get(@intCast(dirfd))) |file| {
            if (!file.inode.mode.isDir())
                return errors.ENOTDIR;
            if (file.path == null)
                return errors.EINVAL;
            from_path = file.path.?;
        } else {
            return errors.EBADF;
        }
    }
    const clone_path = from_path.clone();
    defer clone_path.release();
    const target_path = try fs.path.resolveFrom(path_s, clone_path);
    return try do_statx(target_path.dentry.inode, statxbuf.?);
}
