const fs = @import("../fs.zig");
const Ext2Inode = @import("./inode.zig").Ext2Inode;

pub const Ext2File = struct {
    fn open(_: *fs.File, _: *fs.Inode) !void {
    }

    fn write(base: *fs.File, buf: [*]u8, size: u32) !u32 {
        const ino = base.inode.getImpl(Ext2Inode, "base");
        var to_write = size;
        if (to_write > ino.buff.len - base.pos)
            to_write = ino.buff.len - base.pos;
        @memcpy(ino.buff[base.pos..base.pos + to_write], buf[0..to_write]);
        base.pos += to_write;
        return to_write;
    }

    fn read(base: *fs.File, buf: [*]u8, size: u32) !u32 {
        const ino = base.inode.getImpl(Ext2Inode, "base");
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

pub const Ext2FileOps: fs.FileOps = fs.FileOps {
    .open = Ext2File.open,
    .close = Ext2File.close,
    .write = Ext2File.write,
    .read = Ext2File.read,
    .lseek = null,
};
