const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const dbg = @import("debug");
const krn = @import("../main.zig");

pub fn ftruncate64(fd: u32, length: u32, length_high: u32) !u32 {
    _ = length_high;
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (file.inode.mode.isDir())
            return errors.EISDIR;
        if (!file.inode.mode.isReg()) {
            return errors.EINVAL;
        }
        if (!file.inode.mode.canWrite(file.inode.uid, file.inode.gid)) {
            return errors.EACCES;
        }
        // TODO: implement inode size shrinking
        if (length < file.inode.size)
            return errors.EINVAL;
        const to_write = length - file.inode.size;
        const old_pos = file.pos;
        defer file.pos = old_pos;
        file.pos = file.inode.size;
        var buff: [256]u8 = .{0} ** 256;
        var written: usize = 0;
        while (written < to_write) {
            var single_write = to_write - written;
            if (single_write > 256)
                single_write = 256;
            const res = try file.ops.write(file, &buff, single_write);
            written += res;
        }
        return 0;
    }
    return errors.EBADF;
}
