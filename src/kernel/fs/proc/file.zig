const fs = @import("../fs.zig");
const krn = @import("../../main.zig");
const ProcInode = @import("./inode.zig").ProcInode;

pub const ProcFile = struct {
    fn open(_: *fs.File, _: *fs.Inode) !void {
    }

    fn write(base: *fs.File, buf: [*]const u8, size: u32) !u32 {
        const ino = base.inode.getImpl(ProcInode, "base");
        var to_write = size;
        if (to_write > ino.buff.len - base.pos)
            to_write = ino.buff.len - base.pos;
        @memcpy(ino.buff[base.pos..base.pos + to_write], buf[0..to_write]);
        base.pos += to_write;
        return to_write;
    }

    fn read(base: *fs.File, buf: [*]u8, size: u32) !u32 {
        const ino = base.inode.getImpl(ProcInode, "base");
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

pub const ProcFileOps: fs.FileOps = fs.FileOps {
    .open = ProcFile.open,
    .close = ProcFile.close,
    .write = ProcFile.write,
    .read = ProcFile.read,
    .lseek = null,
};
