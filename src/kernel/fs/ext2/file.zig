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

    // Helper: resolve logical block number -> physical block number
    // Returns:
    //  - Ok(0)    -> sparse hole (no block allocated)
    //  - Ok(n>0)  -> physical block number on disk
    //  - Err(...) -> error (e.g. out of range)
    fn resolve_lbn(ino: *Ext2Inode, ext2_sb: *Ext2Super, lbn: u64) !u32 {
        const bs = ext2_sb.block_size;
        const ptrs_per_block = bs / 4; // 4 bytes per block pointer (u32)

        if (lbn <= 11) {
            // direct
            return ino.data.i_block[@intCast(lbn)];
        }

        // single indirect range: 12 .. 12 + ptrs_per_block - 1
        if (lbn >= 12 and lbn < 12 + ptrs_per_block) {
            const indirect_block = ino.data.i_block[12];
            if (indirect_block == 0) return 0; // hole

            const buf = try ext2_sb.readBlocks(indirect_block, 1);
            defer krn.mm.kfree(buf.ptr);

            // treat buf as array of u32
            const u32_ptr: [*]u32 = @ptrCast(@alignCast(buf.ptr));
            const slice_len = buf.len / 4;
            const slice: []const u32 = u32_ptr[0..slice_len];

            const index: u32 = @intCast(lbn - 12);
            if (index >= slice_len) return krn.errors.PosixError.EINVAL;

            return slice[index];
        }

        // double indirect range: start at 12 + ptrs_per_block
        const dbl_start = 12 + ptrs_per_block;
        const dbl_count = ptrs_per_block * ptrs_per_block;
        if (lbn >= dbl_start and lbn < dbl_start + dbl_count) {
            const dbl_block = ino.data.i_block[13];
            if (dbl_block == 0) return 0; // hole

            // index within the double-indirect space
            const rel = lbn - dbl_start;
            const first_index: u32 = @intCast(rel / ptrs_per_block); // index into dbl_block
            const second_index: u32 = @intCast(rel % ptrs_per_block); // index inside referenced indirect block

            // read double-indirect block (contains ptrs to indirect blocks)
            const dbl_buf = try ext2_sb.readBlocks(dbl_block, 1);
            defer krn.mm.kfree(dbl_buf.ptr);
            const dbl_u32_ptr: [*]u32 = @ptrCast(@alignCast(dbl_buf.ptr));
            const dbl_slice_len = dbl_buf.len / 4;
            if (first_index >= dbl_slice_len) return krn.errors.PosixError.EINVAL;
            const indirect_block_num = dbl_u32_ptr[first_index];
            if (indirect_block_num == 0) return 0; // hole

            // read the indirect block pointed to by double-indirect
            const ind_buf = try ext2_sb.readBlocks(indirect_block_num, 1);
            defer krn.mm.kfree(ind_buf.ptr);
            const ind_u32_ptr: [*]u32 = @ptrCast(@alignCast(ind_buf.ptr));
            const ind_slice_len = ind_buf.len / 4;
            if (second_index >= ind_slice_len) return krn.errors.PosixError.EINVAL;
            return ind_u32_ptr[second_index];
        }

        // triple indirect not implemented here
        return krn.errors.PosixError.EINVAL;
    }

    fn read(base: *fs.File, buf: [*]u8, size: u32) !u32 {
        const ino = base.inode.getImpl(Ext2Inode, "base");
        const ext2_sb = base.inode.sb.getImpl(Ext2Super, "base");

        if (ino.base.mode.isDir()) {
            return krn.errors.PosixError.EISDIR;
        }

        var to_read: u32 = size;
        if (to_read > ino.base.size - base.pos) {
            to_read = ino.base.size - base.pos;
        }
        if (to_read == 0) return 0;

        const bs = ext2_sb.block_size;
        const lbn = base.pos / bs;
        const read_offset: u32 = @intCast(base.pos % bs);

        // resolve lbn -> physical block number
        const pbn = try resolve_lbn(ino, ext2_sb, lbn);

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
