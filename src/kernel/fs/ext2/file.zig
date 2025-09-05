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

        var to_read: u32 = size;
        if (to_read > ino.base.size -| base.pos) {
            to_read = ino.base.size -| base.pos;
        }
        if (to_read == 0) return 0;

        const bs = ext2_sb.block_size;
        const lbn = base.pos / bs;
        const read_offset: u32 = @intCast(base.pos % bs);

        // resolve lbn -> physical block number
        const pbn = try ext2_sb.resolveLbn(ino, lbn);

        // if pbn == 0 => sparse hole: return zeroed bytes up to block boundary
        if (pbn == 0) {
            var zeros_to_copy: u32 = @intCast(to_read);
            if (read_offset + zeros_to_copy > bs) {
                zeros_to_copy = bs - read_offset;
            }
            // fill user buffer with zeros
            @memset(buf[0..zeros_to_copy], 0); // if you don't have std in kernel, use explicit loop
            base.pos += zeros_to_copy;
            return zeros_to_copy;
        }

        // read the actual data block
        const file_buf = try ext2_sb.readBlocks(pbn, 1);
        defer krn.mm.kfree(file_buf.ptr);

        var n: u32 = to_read;
        if (read_offset + n > bs) n = bs - read_offset;

        @memcpy(buf[0..n], file_buf[read_offset..read_offset + n]);
        base.pos += n;
        return  n;
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
