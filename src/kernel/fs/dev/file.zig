const fs = @import("../fs.zig");
const DevInode = @import("./inode.zig").DevInode;

pub const DevFile = struct {
    fn open(_: *fs.File, _: *fs.Inode) !void {
    }

    fn write(base: *fs.File, buf: [*]const u8, size: usize) !usize {
        const ino = base.inode.getImpl(DevInode, "base");
        var to_write = size;
        if (to_write > ino.buff.len - base.pos)
            to_write = ino.buff.len - base.pos;
        @memcpy(ino.buff[base.pos..base.pos + to_write], buf[0..to_write]);
        base.pos += to_write;
        return to_write;
    }

    fn read(base: *fs.File, buf: [*]u8, size: usize) !usize {
        const ino = base.inode.getImpl(DevInode, "base");
        var to_read = size;
        if (to_read > ino.buff.len - base.pos)
            to_read = ino.buff.len - base.pos;
        @memcpy(buf[0..to_read], ino.buff[base.pos..base.pos + to_read]);
        base.pos += to_read;
        return to_read;
    }

    fn close(_: *fs.File) void {
    }
};

pub const DevFileOps: fs.FileOps = fs.FileOps {
    .open = DevFile.open,
    .close = DevFile.close,
    .write = DevFile.write,
    .read = DevFile.read,
    .lseek = null,
};
