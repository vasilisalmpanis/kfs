const fs = @import("../fs.zig");
const kernel = fs.kernel;
const Ext2Inode = @import("inode.zig").Ext2Inode;
const Ext2InodeData = @import("inode.zig").Ext2InodeData;
const Ext2DirEntry = @import("inode.zig").Ext2DirEntry;
const std = @import("std");
const device = @import("drivers").device;
const ext2_inode = @import("./inode.zig");

const EXT2_MAGIC: u32 = 0xEF53;

const BGDT = extern struct {
        bg_block_bitmap: u32,
        bg_inode_bitmap: u32,
        bg_inode_table: u32,
        bg_free_blocks_count: u16,
        bg_free_inodes_count: u16,
        bg_used_dirs_count: u16,
        bg_pad: u16,
        bg_reserved1: u32,
        bg_reserved2: u32,
        bg_reserved3: u32,
};

const Ext2SuperData = extern struct {
        s_inodes_count		        :u32,	// Inodes count
	s_blocks_count			:u32,	// Blocks count
	s_r_blocks_count		:u32,	// Reserved blocks count
	s_free_blocks_count		:u32,	// Free blocks count
	s_free_inodes_count		:u32,	// Free inodes count
	s_first_data_block		:u32,	// First Data Block
	s_log_block_size		:u32,	// Block size
	s_log_frag_size 		:i32,	// Fragment size
	s_blocks_per_group		:u32,	// # Blocks per group
	s_frags_per_group		:u32,	// # Fragments per group
	s_inodes_per_group		:u32,	// # Inodes per group
	s_mtime		        	:u32,	// Mount time
	s_wtime		        	:u32,	// Write time
	s_mnt_count                     :u16,	// Mount count
	s_max_mnt_count 		:i16,	// Maximal mount count
	s_magic		        	:u16,	// Magic signature
	s_state		        	:u16,	// File system state
	s_errors			:u16,	// Behaviour when detecting errors
	s_minor_rev_level 		:u16,	// minor revision level
	s_lastcheck			:u32,	// time of last check
	s_checkinterval	                :u32,	// max. time between checks
	s_creator_os			:u32,	// OS
	s_rev_level			:u32,	// Revision level
	s_def_resuid			:u16,	// Default uid for reserved blocks 
	s_def_resgid			:u16,	// Default gid for reserved blocks

	//
	// These fields are for EXT2_DYNAMIC_REV superblocks only.
	//
	// Note: the difference between the compatible feature set and
	// the incompatible feature set is that if there is a bit set
	// in the incompatible feature set that the kernel doesn't
	// know about, it should refuse to mount the filesystem.
	// 
	// e2fsck's requirements are more strict; if it doesn't know
	// about a feature in either the compatible or incompatible
	// feature set, it must abort and not try to meddle with
	// things it doesn't understand...
	//
	s_first_ino 		    :u32,           // First non-reserved inode */
	s_inode_size 		    :u16,           // size of inode structure */
	s_block_group_nr 	    :u16,           // block group # of this superblock */
	s_feature_compat 	    :u32,           // compatible feature set */
	s_feature_incompat 	    :u32,           // incompatible feature set */
	s_feature_ro_compat         :u32,           // readonly-compatible feature set */
	s_reserved	            :[230] u32,     // Padding to the end of the block */
};

pub const Ext2Super = struct {
    data: Ext2SuperData,
    bgdt: []BGDT,
    base: fs.SuperBlock,
    
    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
        return error.NotImplemented;
    }

    pub fn create(_fs: *fs.FileSystem, dev_file: ?*fs.File) !*fs.SuperBlock {
        if (dev_file == null)
            return kernel.errors.PosixError.ENOTBLK;
        const file: *fs.File = dev_file.?;
        if (kernel.mm.kmalloc(Ext2Super)) |sb| {
            errdefer kernel.mm.kfree(sb);
            sb.base.dev_file = file;
            sb.base.magic = EXT2_MAGIC;
            sb.bgdt.len = 0;
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            errdefer sb.base.inode_map.deinit();

            file.pos = 1024;
            var super_buffer: [1024]u8 align(16) = .{0} ** 1024;
            _ = try file.ops.read(file, &super_buffer, 512);
            _ = try file.ops.read(file, @ptrCast(&super_buffer[512]), 512);
            const ext2_super_data: *Ext2SuperData = @ptrCast(&super_buffer);
            if (ext2_super_data.s_magic != sb.base.magic) {
                return kernel.errors.PosixError.EINVAL;
            }
            sb.data = ext2_super_data.*;
            sb.base.block_size = @as(u32, 1024) << @as(u5, @truncate(sb.data.s_log_block_size));
            var number_of_block_groups: u32 = ext2_super_data.s_blocks_count / ext2_super_data.s_blocks_per_group;
            if (ext2_super_data.s_blocks_count % ext2_super_data.s_blocks_per_group != 0)
                number_of_block_groups += 1;
            if (file.pos % sb.base.block_size != 0)
                file.pos += sb.base.block_size - (file.pos % sb.base.block_size);
            if (kernel.mm.kmallocArray(BGDT, number_of_block_groups)) |bgdt_array| {
                errdefer kernel.mm.kfree(bgdt_array);
                for (0..number_of_block_groups) |idx| {
                    _ = try file.ops.read(file, @ptrCast(&super_buffer), @sizeOf(BGDT));
                    const bgdt: *BGDT = @ptrCast(&super_buffer);
                    bgdt_array[idx] = bgdt.*;
                }
                sb.bgdt = bgdt_array[0..number_of_block_groups];
            }

            const root_inode = try Ext2Inode.new(&sb.base);
            const ext2_root_inode = root_inode.getImpl(Ext2Inode, "base");
            errdefer kernel.mm.kfree(ext2_root_inode);
            try ext2_root_inode.iget(sb, ext2_inode.EXT2_ROOT_INO);
            if (!ext2_root_inode.data.i_mode.isDir()) {
                kernel.logger.WARN("Ext2: corrupted disk\n",.{});
                return kernel.errors.PosixError.ENOENT;
            }

            root_inode.mode = fs.UMode.directory();
            sb.base.inode_map.put(
                root_inode.i_no,
                root_inode
            ) catch |err| {
                kernel.mm.kfree(root_inode);
                kernel.mm.kfree(sb);
                return err;
            };
            const dntry = fs.DEntry.alloc("/", &sb.base, root_inode) catch {
                kernel.mm.kfree(sb);
                return error.OutOfMemory;
            };
            dntry.tree.setup();
            dntry.inode = root_inode;
            sb.base.root = dntry;
            sb.base.list.setup();
            sb.base.ref = kernel.task.RefCount.init();
            sb.base.fs = _fs;
            sb.base.ops = &ext2_super_ops;
            _fs.sbs.add(&sb.base.list);
            return &sb.base;
        }
        return error.OutOfMemory;
    }

    /// Write superblock and bgdt entry to disk after use
    pub fn getFreeBlock(self: *Ext2Super, bgdt_index: u32) !u32 {
        if (bgdt_index >= self.bgdt.len)
            return kernel.errors.PosixError.EINVAL;
        const bgdt_e: *BGDT = &self.bgdt[bgdt_index];

        // Array as big as block_size
        const map = try self.readBlocks(bgdt_e.bg_block_bitmap, 1);
        defer kernel.mm.kfree(map.ptr);
        for (0..self.base.block_size) |idx| {
            var byte: u8 = map[idx];
            if (byte == 0xFF)
                continue;
            for (0..8) |shift| {
                if ((byte & (@as(u8,1) << @intCast(shift))) == 0) {
                    const block_in_group: u32 = @intCast(idx * 8 + shift);
                    const absolute_block: u32 = bgdt_index * self.data.s_blocks_per_group + block_in_group;
                    byte |= (@as(u8,1) << @intCast(shift));
                    map[idx] = byte;
                    _ = try self.writeBuff(bgdt_e.bg_block_bitmap, map.ptr, map.len);
                    @memset(map[0..map.len], 0);
                    _ = try self.writeBuff(absolute_block, map.ptr, map.len);
                    self.data.s_free_blocks_count -= 1;
                    bgdt_e.bg_free_blocks_count -= 1;
                    return absolute_block;
                }
            }
        }
        return kernel.errors.PosixError.ENOSPC;
    }

    pub fn writeSuper(self: *Ext2Super) !void {
        if (self.data.s_magic != EXT2_MAGIC) {
            kernel.logger.ERROR(
                "Ext2Super.writeSuper(): ext2 magic corrupted: {x}, should be: {x}",
                .{self.data.s_magic, EXT2_MAGIC}
            );
            return kernel.errors.PosixError.EINVAL;
        }
        self.data.s_wtime = @intCast(kernel.cmos.toUnixSeconds(kernel.cmos));
        var buff: [1024]u8 = .{0} ** 1024;
        const src: [*]const u8 = @ptrCast(&self.data);
        const size = @sizeOf(Ext2SuperData);
        @memcpy(
            buff[0..size],
            src[0..size]
        );
        const block: u32 = if (self.base.block_size == 1024) 1 else 0;
        const offset: u32 = if (self.base.block_size == 1024) 0 else 1024;
        _ = try self.writeBuffAtOffset(block, &buff, size, offset);
    }

    pub fn writeGDTEntry(self: *Ext2Super, entry_idx: u32) !void {
        const gdt_start_block: u32 = if (self.base.block_size == 1024) 2 else 1;
        const byte_off = entry_idx * @sizeOf(BGDT);
        const block = gdt_start_block + (byte_off / self.base.block_size);
        const offset: u32 = byte_off % self.base.block_size;

        var block_buff = try self.readBlocks(block, 1);
        defer kernel.mm.kfree(block_buff.ptr);

        const src = &self.bgdt[entry_idx];
        @memcpy(
            block_buff[offset..offset + @sizeOf(BGDT)],
            @as([*]const u8, @ptrCast(src))[0..@sizeOf(BGDT)]
        );

        _ = try self.writeBuff(
            block,
            block_buff.ptr,
            self.base.block_size
        );
    }


    pub fn readBlocks(sb: *Ext2Super, block: usize, count: usize) ![]u8 {
        const alloc_size: usize = sb.base.block_size * count;
        if (kernel.mm.kmallocArray(u8, alloc_size)) |raw_buff| {
            errdefer kernel.mm.kfree(raw_buff);
            @memset(raw_buff[0..alloc_size], 0);
            sb.base.dev_file.?.pos = sb.base.block_size * block;
            var read: usize = 0;
            while (read < alloc_size) {
                const single_read: usize = try sb.base.dev_file.?.ops.read(
                    sb.base.dev_file.?,
                    @ptrCast(&raw_buff[read]),
                    alloc_size - read
                );
                // FIXME:
                if (single_read == 0)
                    break;
                read += single_read;
            }
            return raw_buff[0..alloc_size];
        } else {
            kernel.logger.INFO("Ext2: Allocate buffer: Out of Memory", .{});
            return kernel.errors.PosixError.ENOMEM;
        }
    }

    pub fn writeBuffAtOffset(
        sb: *Ext2Super,
        block: u32,
        buff: [*]const u8,
        size: usize,
        offset: usize
    ) !usize {
        var to_write: usize = size;
        sb.base.dev_file.?.pos = sb.base.block_size * block + offset;
        var written: usize = 0;
        while (written < size) {
            const single_write: usize = try sb.base.dev_file.?.ops.write(
                sb.base.dev_file.?,
                @ptrCast(&buff[written]),
                to_write
            );
            sb.base.dev_file.?.pos += single_write;
            to_write -= single_write;
            if (single_write == 0)
                break;
            written += single_write;
        }
        return written;
    }

    pub fn writeBuff(sb: *Ext2Super, block: u32, buff: [*]const u8, size: usize) !usize {
        return try sb.writeBuffAtOffset(block, buff, size, 0);
    }

    pub fn getFirstInodeIdx(self: *Ext2Super) u32 {
        if (self.data.s_rev_level == 0) {
            return 11;
        } else {
            return self.data.s_first_ino;
        }
    }

    // Helper: resolve logical block number -> physical block number
    // Returns:
    //  - Ok(0)    -> sparse hole (no block allocated)
    //  - Ok(n>0)  -> physical block number on disk
    //  - Err(...) -> error (e.g. out of range)
    pub fn resolveLbn(ext2_sb: *Ext2Super, ino: *Ext2Inode, lbn: u64) !u32 {
        const bs = ext2_sb.base.block_size;
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
            defer kernel.mm.kfree(buf.ptr);

            // treat buf as array of u32
            const u32_ptr: [*]u32 = @ptrCast(@alignCast(buf.ptr));
            const slice_len = buf.len / 4;
            const slice: []const u32 = u32_ptr[0..slice_len];

            const index: u32 = @intCast(lbn - 12);
            if (index >= slice_len) return kernel.errors.PosixError.EINVAL;

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
            defer kernel.mm.kfree(dbl_buf.ptr);
            const dbl_u32_ptr: [*]u32 = @ptrCast(@alignCast(dbl_buf.ptr));
            const dbl_slice_len = dbl_buf.len / 4;
            if (first_index >= dbl_slice_len) return kernel.errors.PosixError.EINVAL;
            const indirect_block_num = dbl_u32_ptr[first_index];
            if (indirect_block_num == 0) return 0; // hole

            // read the indirect block pointed to by double-indirect
            const ind_buf = try ext2_sb.readBlocks(indirect_block_num, 1);
            defer kernel.mm.kfree(ind_buf.ptr);
            const ind_u32_ptr: [*]u32 = @ptrCast(@alignCast(ind_buf.ptr));
            const ind_slice_len = ind_buf.len / 4;
            if (second_index >= ind_slice_len) return kernel.errors.PosixError.EINVAL;
            return ind_u32_ptr[second_index];
        }

        const trpl_start = dbl_start + dbl_count;
        const trpl_count = dbl_count * ptrs_per_block;
        if (lbn >= trpl_start and lbn < trpl_start + trpl_count) {
            const trpl_block: u32 = ino.data.i_block[14];
            if (trpl_block == 0) return 0;

            const trpl_ind_buf: []u32 = @ptrCast(@alignCast(
                try ext2_sb.readBlocks(trpl_block, 1)
            ));

            defer kernel.mm.kfree(trpl_ind_buf.ptr);

            const rel = lbn - trpl_start;
            const rem: u32 = @intCast(rel % (ptrs_per_block * ptrs_per_block));

            const first_index: u32 = @intCast(rel / (ptrs_per_block * ptrs_per_block));
            const second_index: u32 = @intCast(rem / ptrs_per_block);
            const third_index: u32 = @intCast(rem % ptrs_per_block);

            if (first_index >= trpl_ind_buf.len) {
                return kernel.errors.PosixError.EINVAL;
            }
            const dbl_indirect_block_num = trpl_ind_buf[first_index];
            if (dbl_indirect_block_num == 0) return 0;

            const dbl_ind_buf: []u32 = @ptrCast(@alignCast(
                try ext2_sb.readBlocks(dbl_indirect_block_num, 1)
            ));
            defer kernel.mm.kfree(dbl_ind_buf.ptr);

            if (second_index >= dbl_ind_buf.len) {
                return kernel.errors.PosixError.EINVAL;
            }
            const indirect_block_num = dbl_ind_buf[second_index];
            if (indirect_block_num == 0) return 0;

            const ind_buf: []u32 = @ptrCast(@alignCast(
                try ext2_sb.readBlocks(indirect_block_num, 1)
            ));
            defer kernel.mm.kfree(ind_buf.ptr);

            if (third_index >= ind_buf.len) {
                return kernel.errors.PosixError.EINVAL;
            }
            return ind_buf[third_index];
        }
        return kernel.errors.PosixError.EINVAL;
    }

    pub inline fn freeBlocksCount(self: *Ext2Super) u32 {
        var count: u32 = 0;
        for (self.bgdt) |bgd| {
            count += bgd.bg_free_blocks_count;
        }
        return count;
    }

    pub inline fn freeInodesCount(self: *Ext2Super) u32 {
        var count: u32 = 0;
        for (self.bgdt) |bgd| {
            count += bgd.bg_free_inodes_count;
        }
        return count;
    }

    pub fn statfs(base: *fs.SuperBlock) !fs.Statfs {
        const ext2_sb = base.getImpl(Ext2Super, "base");
        const bfree: u32 = ext2_sb.freeBlocksCount();
        const ffree: u32 = ext2_sb.freeInodesCount();
        return fs.Statfs{
            .type = base.magic,
            .bsize = base.block_size,
            .blocks = ext2_sb.data.s_blocks_count,
            .bfree = bfree,
            .bavail = bfree - ext2_sb.data.s_r_blocks_count,
            .files = ext2_sb.data.s_inodes_count,
            .ffree = ffree,
            .namelen = 255,
            .flags = 0,
            .frsize = 0,
            .fsid = 0,
        };
    }

    fn commitBGDTEntries(self: *Ext2Super, bgdt_idxs: []bool) !void {
        for (bgdt_idxs, 0..) |used, gdt_idx| {
            if (used) {
                try self.writeGDTEntry(@intCast(gdt_idx));
            }
        }
    }

    pub fn freeInodeBlocks(self: *Ext2Super, ino: *Ext2Inode) !void {
        const bs = self.base.block_size;
        const ptrs_per_block = bs / 4; // 4 bytes per block pointer (u32)
        const max_iblocks_idx = ino.maxBlockIdx();
        const blocks_used = ino.data.i_blocks * 512 / self.base.block_size;
        var blocks_freed: u32 = 0;
        if (blocks_used == 0)
            return ;

        var changed_bgds = kernel.mm.kmallocSlice(bool, self.bgdt.len) orelse
            return kernel.errors.PosixError.ENOMEM;
        @memset(changed_bgds, false);
        defer self.commitBGDTEntries(changed_bgds) catch {};
        defer kernel.mm.kfree(changed_bgds.ptr);
        const max_direct = if (max_iblocks_idx > 11)
            12 else max_iblocks_idx + 1;
        for (0..max_direct) |idx| {
            const block = ino.data.i_block[idx];
            if (block != 0) {
                const bgd_idx = try self.freeBlock(block);
                changed_bgds[bgd_idx] = true;
                blocks_freed += 1;
                if (blocks_freed >= blocks_used)
                    return ;
            }
        }

        if (max_iblocks_idx < 12)
            return;
        const indirect_block = ino.data.i_block[12];
        if (indirect_block != 0) {
            const buf = try self.readBlocks(indirect_block, 1);
            defer kernel.mm.kfree(buf.ptr);
            const u32_ptr: [*]u32 = @ptrCast(@alignCast(buf.ptr));
            const slice_len = buf.len / 4;
            const slice: []const u32 = u32_ptr[0..slice_len];
            for(0..ptrs_per_block) |index| {
                if (index >= slice_len)
                    return kernel.errors.PosixError.EINVAL;
                const block = slice[index];
                if (block != 0) {
                    const bgd_idx = try self.freeBlock(block);
                    changed_bgds[bgd_idx] = true;
                    blocks_freed += 1;
                    if (blocks_used >= blocks_freed)
                        break ;
                }
            }
            const bgd_idx = try self.freeBlock(indirect_block);
            changed_bgds[bgd_idx] = true;
            blocks_freed += 1;
            if (blocks_freed >= blocks_used)
                return ;
        }

        if (max_iblocks_idx < 13)
            return;
        const dbl_block = ino.data.i_block[13];
        if (dbl_block != 0) {
            const dbl_buf = try self.readBlocks(dbl_block, 1);
            defer kernel.mm.kfree(dbl_buf.ptr);
            const dbl_u32_ptr: [*]u32 = @ptrCast(@alignCast(dbl_buf.ptr));
            const dbl_slice_len = dbl_buf.len / 4;
            for (0..dbl_slice_len) |dbl_idx| {

                const indirect_block_num = dbl_u32_ptr[dbl_idx];
                if (indirect_block_num == 0)
                    continue ;

                const ind_buf = try self.readBlocks(indirect_block_num, 1);
                defer kernel.mm.kfree(ind_buf.ptr);
                const ind_u32_ptr: [*]u32 = @ptrCast(@alignCast(ind_buf.ptr));
                const ind_slice_len = ind_buf.len / 4;
                for (0..ind_slice_len) |idx| {
                    const block = ind_u32_ptr[idx];
                    if (block != 0) {
                        const bgd_idx = try self.freeBlock(block);
                        changed_bgds[bgd_idx] = true;
                        blocks_freed += 1;
                        if (blocks_freed >= blocks_used)
                            break ;
                    }
                }
                const bgd_idx = try self.freeBlock(indirect_block_num);
                changed_bgds[bgd_idx] = true;
                blocks_freed += 1;
                if (blocks_freed >= blocks_used)
                    break ;
            }
            const bgd_idx = try self.freeBlock(dbl_block);
            changed_bgds[bgd_idx] = true;
            blocks_freed += 1;
            if (blocks_freed >= blocks_used)
                return ;
        }
        if (max_iblocks_idx < 14)
            return;

        const trpl_block: u32 = ino.data.i_block[14];
        if (trpl_block == 0)
            return ;
        const trpl_ind_buf: []u32 = @ptrCast(@alignCast(
            try self.readBlocks(trpl_block, 1)
        ));
        defer kernel.mm.kfree(trpl_ind_buf.ptr);
        for (0..trpl_ind_buf.len) |first_idx| {
            const dbl_indirect_block_num = trpl_ind_buf[first_idx];
            if (dbl_indirect_block_num == 0)
                continue ;

            const dbl_ind_buf: []u32 = @ptrCast(@alignCast(
                try self.readBlocks(dbl_indirect_block_num, 1)
            ));
            defer kernel.mm.kfree(dbl_ind_buf.ptr);
            for (0..dbl_ind_buf.len) |second_idx| {
                const indirect_block_num = dbl_ind_buf[second_idx];
                if (indirect_block_num == 0)
                    continue ;

                const ind_buf: []u32 = @ptrCast(@alignCast(
                    try self.readBlocks(indirect_block_num, 1)
                ));
                defer kernel.mm.kfree(ind_buf.ptr);
                for (0..ind_buf.len) |third_idx| {
                    const block = ind_buf[third_idx];
                    if (block != 0) {
                        const bgd_idx = try self.freeBlock(block);
                        changed_bgds[bgd_idx] = true;
                        blocks_freed += 1;
                        if (blocks_freed >= blocks_used)
                            break ;
                    }
                }
                const bgd_idx = try self.freeBlock(indirect_block_num);
                changed_bgds[bgd_idx] = true;
                blocks_freed += 1;
                if (blocks_freed >= blocks_used)
                    break ;
            }
            const bgd_idx = try self.freeBlock(dbl_indirect_block_num);
            changed_bgds[bgd_idx] = true;
            blocks_freed += 1;
            if (blocks_freed >= blocks_used)
                break ;
        }
        const bgd_idx = try self.freeBlock(trpl_block);
        changed_bgds[bgd_idx] = true;
        blocks_freed += 1;
        if (blocks_freed >= blocks_used)
            return ;
    }

    fn freeBlock(self: *Ext2Super, block: u32) !u32 {
        const bgdt_idx = block / self.data.s_blocks_per_group;
        const block_idx = block % self.data.s_blocks_per_group;
        const bitmap_byte = block_idx / 8;
        const bitmap_bit: u8 = @intCast(block_idx % 8);
        var bgd = &self.bgdt[bgdt_idx];
        const block_bitmap = try self.readBlocks(bgd.bg_block_bitmap, 1);
        defer kernel.mm.kfree(block_bitmap.ptr);
        var current_byte = block_bitmap[bitmap_byte];
        const mask: u8 = ~(@as(u8, 1) << @intCast(bitmap_bit));
        if (current_byte & ~mask == 0)
            kernel.logger.WARN("Freeing block which is already free", .{});
        current_byte = current_byte & mask;
        block_bitmap[bitmap_byte] = current_byte;
        _ = try self.writeBuff(
            bgd.bg_block_bitmap, 
            block_bitmap.ptr, 
            block_bitmap.len
        );
        self.data.s_free_blocks_count += 1;
        bgd.bg_free_blocks_count += 1;
        return bgdt_idx;
    }

    fn destroyInode(self: *fs.SuperBlock, base: *fs.Inode) !void {
        const ext2_sb = self.getImpl(Ext2Super, "base");
        const ext2_target_inode = base.getImpl(Ext2Inode, "base");

        if (base.links != 0) {
            return ;
        }

        // Inode Bitmap
        const bgdt_idx = (base.i_no - 1) / ext2_sb.data.s_inodes_per_group;
        const bgdt_entry = &ext2_sb.bgdt[bgdt_idx];
        const inode_index = (base.i_no - 1) % ext2_sb.data.s_inodes_per_group;

        const bgdt_bitmap_slice = try ext2_sb.readBlocks(bgdt_entry.bg_inode_bitmap, 1);
        defer kernel.mm.kfree(bgdt_bitmap_slice.ptr);

        const bit = (base.i_no - 1) % ext2_sb.data.s_inodes_per_group;
        const byte = bit >> 3;
        const mask: u8 = ~(@as(u8, 1) << @intCast(bit & 7));

        bgdt_bitmap_slice[byte] &= mask;
        _ = try ext2_sb.writeBuff(
            bgdt_entry.bg_inode_bitmap,
            bgdt_bitmap_slice.ptr,
            bgdt_bitmap_slice.len
        );

        if (ext2_target_inode.base.mode.isDir()) {
            bgdt_entry.bg_used_dirs_count -= 1;
        }

        // Inode table
        var rel_offset = inode_index * ext2_sb.data.s_inode_size;
        const block = bgdt_entry.bg_inode_table + (rel_offset >> @as(u5, @truncate(ext2_sb.data.s_log_block_size + 10)));
        const size = @sizeOf(Ext2InodeData);

        const bgdt_inode_slice = try ext2_sb.readBlocks(block, 1);
        defer kernel.mm.kfree(bgdt_inode_slice.ptr);

        rel_offset &= (ext2_sb.base.block_size - 1);
        @memset(bgdt_inode_slice[rel_offset..rel_offset + size], 0);
        _ = try ext2_sb.writeBuff(block, bgdt_inode_slice.ptr, bgdt_inode_slice.len);

        // Free blocks
        try ext2_sb.freeInodeBlocks(ext2_target_inode);

        bgdt_entry.bg_free_inodes_count += 1;
        ext2_sb.data.s_free_inodes_count += 1;
        try ext2_sb.writeGDTEntry(bgdt_idx);
        try ext2_sb.writeSuper();
        // Free blocks in sb
        // Free Inode in sb
        kernel.mm.kfree(ext2_target_inode);
    }
};

const ext2_super_ops = fs.SuperOps{
    .alloc_inode = Ext2Super.allocInode,
    .destroy_inode = Ext2Super.destroyInode,
    .statfs = Ext2Super.statfs,
};
