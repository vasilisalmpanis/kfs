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
    fn write(base: *fs.File, buf: [*]const u8, size: usize) !usize {
        const sb: *fs.SuperBlock = if (base.inode.sb) |_s| _s else return krn.errors.PosixError.EINVAL;
        const ino = base.inode.getImpl(Ext2Inode, "base");
        const ext2_sb = sb.getImpl(Ext2Super, "base");

        if (ino.base.mode.isDir()) {
            return krn.errors.PosixError.EISDIR;
        }

        var to_write: usize = size;
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

        const off: usize = base.pos % bs;
        if (off + to_write > bs) {
            to_write = bs - off;
        }
        @memcpy(buff[off..off + to_write], buf[0..to_write]);
        _ = try ext2_sb.writeBuff(pbn, buff.ptr, buff.len);

        base.pos += to_write;
        if (base.pos > ino.base.size) {
            ino.base.size = base.pos;
            ino.data.i_size = @intCast(ino.base.size);
            try ino.iput();
        }
        return to_write;
    }

    fn read(base: *fs.File, buf: [*]u8, size: usize) !usize {
        const sb: *fs.SuperBlock = if (base.inode.sb) |_s| _s else
            return krn.errors.PosixError.EINVAL;
        const ino = base.inode.getImpl(Ext2Inode, "base");
        const ext2_sb = sb.getImpl(Ext2Super, "base");

        if (ino.base.mode.isDir()) {
            return krn.errors.PosixError.EISDIR;
        }

        var to_read: usize = size;
        if (to_read > ino.base.size -| base.pos) {
            to_read = ino.base.size -| base.pos;
        }
        if (to_read == 0)
            return 0;

        const bs = ext2_sb.base.block_size;
        const read_offset: usize = base.pos % bs;

        const fisrt_lbn = base.pos / bs;
        var last_lbn = (base.pos + to_read) / bs;
        if ((base.pos + to_read) % bs != 0)
            last_lbn += 1;
        var last_contig_lbn: usize = fisrt_lbn;

        var first_pbn: usize = 0;
        var contig_pbn_count: usize = 0;
        var prev_pbn: usize = 0;

        for (fisrt_lbn..last_lbn) |_lbn| {
            const pbn = try ext2_sb.resolveLbn(ino, _lbn);
            if (first_pbn == 0) {
                first_pbn = pbn;
            }
            // if pbn == 0 => sparse hole: return zeroed bytes up to block boundary
            if (pbn == 0 and _lbn == fisrt_lbn) {
                var zeros_to_copy: usize = @intCast(to_read);
                if (read_offset + zeros_to_copy > bs) {
                    zeros_to_copy = bs - read_offset;
                }
                // fill user buffer with zeros
                @memset(buf[0..zeros_to_copy], 0); // if you don't have std in kernel, use explicit loop
                base.pos += zeros_to_copy;
                return zeros_to_copy;
            } else if (pbn == 0) {
                break;
            }
            if (prev_pbn != 0 and prev_pbn + 1 != pbn) {
                break ;
            }
            prev_pbn = pbn;
            contig_pbn_count += 1;
            last_contig_lbn = _lbn;
        }

        // read the actual data block
        const file_buf = try ext2_sb.readBlocks(first_pbn, contig_pbn_count);
        defer krn.mm.kfree(file_buf.ptr);

        var bytes_read: usize = file_buf.len - read_offset;
        if (bytes_read > to_read) {
            bytes_read = to_read;
        }

        @memcpy(buf[0..bytes_read], file_buf[read_offset..read_offset + bytes_read]);
        base.pos += bytes_read;
        return bytes_read;
    }

    fn close(_: *fs.File) void {
    }

    fn readdir(base: *fs.File, buf: []u8) !usize {
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

        const blk_index: usize = @intCast(pos / block_size);
        var offset: usize = @intCast(pos % block_size);

        if (blk_index >= ext2_dir_inode.maxBlockIdx()) {
            krn.logger.INFO("invalid blk index {d}\n", .{blk_index});
            return krn.errors.PosixError.ENOENT;
        }

        const block: usize = ext2_dir_inode.data.i_block[blk_index];
        const block_slice: []u8 = try ext2_super.readBlocks(block, 1);
        defer krn.mm.kfree(block_slice.ptr);
        var bytes_written: usize = 0;

        while (bytes_written < buf.len and offset < block_size) {
            var ext_dir: *Ext2DirEntry = @ptrFromInt(@intFromPtr(block_slice.ptr) + offset);

            if (ext_dir.inode == 0 or ext_dir.rec_len == 0) {
                krn.logger.INFO("Corrupted directory\n", .{});
                return krn.errors.PosixError.ENOENT;
            }

            const entry_size: usize = @sizeOf(fs.LinuxDirent) + ext_dir.getName().len + 1; // For null termination
            if (entry_size > buf.len - bytes_written)
                return krn.errors.PosixError.EINVAL;
            const dirent: *fs.LinuxDirent = @ptrFromInt(@intFromPtr(buf.ptr) + bytes_written);

            dirent.ino = ext_dir.inode;
            var reclen: u16 = @intCast(entry_size);
            const _off = reclen % @sizeOf(usize);
            if (_off != 0)
                reclen += @as(u16, @intCast(@sizeOf(usize))) - _off;
            dirent.reclen = reclen;
            dirent.off = base.pos + ext_dir.rec_len;
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
