const std = @import("std");

const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const krn = @import("../main.zig");

const Statfs64 = extern struct {
	f_type: u32,
	f_bsize: u32,
	f_blocks: u64,
	f_bfree: u64,
	f_bavail: u64,
	f_files: u64,
	f_ffree: u64,
	f_fsid: i64,
	f_namelen: u32,
	f_frsize: u32,
	f_flags: u32,
	f_spare: [4]u32 = .{0} ** 4,

    pub fn fromStatfs(stat: fs.Statfs) Statfs64 {
        return Statfs64{
            .f_type = @intCast(stat.type),
            .f_bsize = @intCast(stat.bsize),
            .f_blocks = @intCast(stat.blocks),
            .f_bfree = @intCast(stat.bfree),
            .f_bavail = @intCast(stat.bavail),
            .f_files = @intCast(stat.files),
            .f_ffree = @intCast(stat.ffree),
            .f_fsid = @intCast(stat.fsid),
            .f_namelen = @intCast(stat.namelen),
            .f_frsize = if (stat.frsize == 0)
                    @intCast(stat.bsize) else @intCast(stat.frsize),
            .f_flags = @intCast(stat.flags),
        };
    }
};

pub fn statfs64(path: ?[*:0]const u8, size: u32, buf: ?*Statfs64) !u32 {
    if (path == null or buf == null) {
        return errors.EFAULT;
    }
    if (size != @sizeOf(Statfs64))
        return errors.EINVAL;
    const _path: []const u8 = std.mem.span(path.?);
    const resolved = try fs.path.resolve(_path);
    if (resolved.dentry.sb.ops.statfs) |statfs| {
        const stat = try statfs(resolved.dentry.sb);
        buf.?.* = Statfs64.fromStatfs(stat);
        return 0;
    }
    return errors.ENOSYS;
}
