const krn = @import("../../main.zig");
const fs = @import("../fs.zig");
const std = @import("std");
const Ext2Inode = @import("./inode.zig").Ext2Inode;
const Ext2Super = @import("./super.zig").Ext2Super;
const Ext2DirEntry = @import("./inode.zig").Ext2DirEntry;

pub const Ext2File = struct {
    fn open(base: *fs.File, _: *fs.Inode) !void {
        if (base.path == null) return krn.errors.PosixError.EINVAL;
        krn.logger.INFO("ext2 file open {s}", .{base.path.?.dentry.name});
    }

    // fn write(base: *fs.File, _: [*]u8, size: u32) !u32 {
    //     const ino = base.inode.getImpl(Ext2Inode, "base");
    //     var to_write = size;
    //     if (to_write > ino.base.size - base.pos)
    //         to_write = ino.base.size - base.pos;
    //     // @memcpy(ino.buff[base.pos..base.pos + to_write], buf[0..to_write]);
    //     base.pos += to_write;
    //     return to_write;
    // }
    fn write(base: *fs.File, buf: [*]const u8, size: u32) !u32 {
        const sb: *fs.SuperBlock = if (base.inode.sb) |_s| _s else return krn.errors.PosixError.EINVAL;
        const ino = base.inode.getImpl(Ext2Inode, "base");
        const ext2_sb = sb.getImpl(Ext2Super, "base");

        if (ino.base.mode.isDir()) {
            return krn.errors.PosixError.EISDIR;
        }

        var to_write: u32 = size;
        // if (to_write > ino.base.size -| base.pos) {
        //     to_write = ino.base.size -| base.pos;
        // }
        if (to_write == 0)
            return 0;
        if (to_write > ext2_sb.base.block_size) {
            to_write = ext2_sb.base.block_size;
        }

        const bs = ext2_sb.base.block_size;
        const lbn = base.pos / bs;
        // const write_offset: u32 = @intCast(base.pos % bs);

        // resolve lbn -> physical block number
        var pbn = try ext2_sb.resolveLbn(ino, lbn);

        // if pbn == 0 => sparse hole: return zeroed bytes up to block boundary
        if (pbn == 0) {
            pbn = try ino.allocBlock();
        }

        const buff = try ext2_sb.readBlocks(pbn, 1);
        defer krn.mm.kfree(buff.ptr);

        const off: u32 = base.pos % bs;
        if (off + to_write > bs) {
            to_write = bs - off;
        }
        @memcpy(buff[off..off + to_write], buf[0..to_write]);
        _ = try ext2_sb.writeBuff(pbn, buff.ptr, buff.len);

        base.pos += to_write;
        if (base.pos > ino.base.size) {
            ino.base.size = base.pos;
            ino.data.i_size = ino.base.size;
            try ino.iput();
        }
        return to_write;
    }

    fn read(base: *fs.File, buf: [*]u8, size: u32) !u32 {
        const sb: *fs.SuperBlock = if (base.inode.sb) |_s| _s else return krn.errors.PosixError.EINVAL;
        const ino = base.inode.getImpl(Ext2Inode, "base");
        const ext2_sb = sb.getImpl(Ext2Super, "base");

        if (ino.base.mode.isDir()) {
            return krn.errors.PosixError.EISDIR;
        }

        var to_read: u32 = size;
        if (to_read > ino.base.size -| base.pos) {
            to_read = ino.base.size -| base.pos;
        }
        if (to_read == 0) return 0;

        const bs = ext2_sb.base.block_size;
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

    fn readdir(base: *fs.File, buf: []u8) !u32 {
        const sb: *fs.SuperBlock = if (base.inode.sb) |_s| _s else return krn.errors.PosixError.EINVAL;
        if (base.path == null) return krn.errors.PosixError.EINVAL;

        if (!base.path.?.dentry.inode.mode.isDir()) {
            return krn.errors.PosixError.ENOTDIR;
        }
        const ext2_dir_inode = base.inode.getImpl(Ext2Inode, "base");
        const ext2_super = sb.getImpl(Ext2Super, "base");

        const block_size = ext2_super.base.block_size;
        const pos = base.pos;

        if (pos >= ext2_dir_inode.data.i_size) {
            return 0;
        }

        const blk_index: u32 = @intCast(pos / block_size);
        var offset: u32 = @intCast(pos % block_size);

        if (blk_index >= ext2_dir_inode.maxBlockIdx()) {
            krn.logger.INFO("invalid blk index {d}\n", .{blk_index});
            return krn.errors.PosixError.ENOENT;
        }

        const block: u32 = ext2_dir_inode.data.i_block[blk_index];
        const block_slice: []u8 = try ext2_super.readBlocks(block, 1);
        defer krn.mm.kfree(block_slice.ptr);
        var bytes_written: u32 = 0;

        while (bytes_written < buf.len and offset < block_size) {
            var ext_dir: *Ext2DirEntry = @ptrFromInt(@intFromPtr(block_slice.ptr) + offset);

            if (ext_dir.inode == 0 or ext_dir.rec_len == 0) {
                krn.logger.INFO("Corrupted directory\n", .{});
                return krn.errors.PosixError.ENOENT;
            }

            const entry_size: u32 = @sizeOf(fs.LinuxDirent) + ext_dir.getName().len + 1; // For null termination
            if (entry_size > buf.len - bytes_written)
                return krn.errors.PosixError.EINVAL;
            const dirent: *fs.LinuxDirent = @ptrFromInt(@intFromPtr(buf.ptr) + bytes_written);

            dirent.ino = ext_dir.inode;
            dirent.off = base.pos;
            dirent.reclen = @intCast(entry_size);
            if (dirent.reclen % @sizeOf(usize) != 0) dirent.reclen += @sizeOf(usize) - (dirent.reclen % @sizeOf(usize));
            switch (ext_dir.file_type) {
                0 => dirent.type = fs.DT_UNKNOWN,
                1 => dirent.type = fs.DT_REG,
                2 => dirent.type = fs.DT_DIR,
                3 => dirent.type = fs.DT_CHR,
                4 => dirent.type = fs.DT_BLK,
                5 => dirent.type = fs.DT_FIFO,
                6 => dirent.type = fs.DT_SOCK,
                7 => dirent.type = fs.DT_LNK,
                else => {
                    dirent.type = fs.DT_UNKNOWN;
                },
            }
            const name = ext_dir.getName();
            const name_buff: [*]u8 = @ptrFromInt(@intFromPtr(buf.ptr) + @sizeOf(fs.LinuxDirent) + bytes_written);
            @memcpy(name_buff[0..name.len], name);
            name_buff[name.len] = 0;
            base.pos += ext_dir.rec_len;
            offset += ext_dir.rec_len;
            bytes_written += dirent.reclen;
        }
        return bytes_written;
    }

};

pub const Ext2FileOps: fs.FileOps = fs.FileOps {
    .open = Ext2File.open,
    .close = Ext2File.close,
    .write = Ext2File.write,
    .read = Ext2File.read,
    .lseek = null,
    .readdir = Ext2File.readdir,
};
