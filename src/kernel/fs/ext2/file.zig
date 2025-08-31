const krn = @import("../../main.zig");
const fs = @import("../fs.zig");
const Ext2Inode = @import("./inode.zig").Ext2Inode;
const Ext2Super = @import("./super.zig").Ext2Super;

pub const Ext2File = struct {
    fn open(_: *fs.File, _: *fs.Inode) !void {
        krn.logger.INFO("ext2 file open", .{});
    }

    fn write(base: *fs.File, _: [*]u8, size: u32) !u32 {
        const ino = base.inode.getImpl(Ext2Inode, "base");
        var to_write = size;
        if (to_write > ino.base.size - base.pos)
            to_write = ino.base.size - base.pos;
        // @memcpy(ino.buff[base.pos..base.pos + to_write], buf[0..to_write]);
        base.pos += to_write;
        return to_write;
    }

    fn read(base: *fs.File, buf: [*]u8, size: u32) !u32 {
        const ino = base.inode.getImpl(Ext2Inode, "base");
        const ext2_sb = base.inode.sb.getImpl(Ext2Super, "base");
        if (ino.base.mode.isDir()) {
            return krn.errors.PosixError.EISDIR;
        }
        var to_read = size;
        if (to_read > ino.base.size - base.pos)
            to_read = ino.base.size - base.pos;
        if (to_read < 1) {
            return 0;
        }
        const lbn_offset = base.pos / ext2_sb.block_size;
        if (lbn_offset > 11) {
            return 0;
        }
        const block = ino.data.i_block[lbn_offset];
        const file_buff = try ext2_sb.readBlocks(block, 1);

        const read_offset = base.pos % ext2_sb.block_size;
        if (read_offset + to_read > ext2_sb.block_size) {
            to_read = ext2_sb.block_size - read_offset;
        }
        @memcpy(buf[0..to_read], file_buff[read_offset..read_offset + to_read]);
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
