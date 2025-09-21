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
    s_inodes_count		    :u32,	// Inodes count
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
	s_mnt_count			    :u16,	// Mount count
	s_max_mnt_count 		:i16,	// Maximal mount count
	s_magic		        	:u16,	// Magic signature
	s_state		        	:u16,	// File system state
	s_errors			    :u16,	// Behaviour when detecting errors
	s_minor_rev_level 		:u16,	// minor revision level
	s_lastcheck			    :u32,	// time of last check
	s_checkinterval	        :u32,	// max. time between checks
	s_creator_os			:u32,	// OS
	s_rev_level			    :u32,	// Revision level
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
	s_feature_ro_compat     :u32,           // readonly-compatible feature set */
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
            sb.bgdt.len = 0;
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            errdefer sb.base.inode_map.deinit();

            file.pos = 1024;
            var super_buffer: [1024]u8 align(16) = .{0} ** 1024;
            _ = try file.ops.read(file, &super_buffer, 512);
            _ = try file.ops.read(file, @ptrCast(&super_buffer[512]), 512);
            const ext2_super_data: *Ext2SuperData = @ptrCast(&super_buffer);
            if (ext2_super_data.s_magic != EXT2_MAGIC) {
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

            root_inode.mode = fs.UMode{
                // This should come from mount.
                .type   = fs.S_IFDIR,
                .usr    = 0o7,
                .grp    = 0o5,
                .other  = 0o5,
            };
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

    pub fn writeSuper(self: *Ext2Super) !void {
        if (self.data.s_magic != EXT2_MAGIC) {
            kernel.logger.ERROR(
                "Ext2Super.writeSuper(): ext2 magic corrupted: {x}, should be: {x}",
                .{self.data.s_magic, EXT2_MAGIC}
            );
            return kernel.errors.PosixError.EINVAL;
        }
        self.data.s_wtime = @intCast(kernel.cmos.toUnixSeconds());
        var buff: [1024]u8 = .{0} ** 1024;
        const src: [*]const u8 = @ptrCast(&self.data);
        const size = @sizeOf(Ext2SuperData);
        @memcpy(
            buff[0..size],
            src[0..size]
        );
        const block = 1042 / self.base.block_size;
        _ = try self.writeBuff(block, &buff, size);
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


    pub fn readBlocks(sb: *Ext2Super, block: u32, count: u32) ![]u8 {
        const alloc_size: u32 = sb.base.block_size * count;
        if (kernel.mm.kmallocArray(u8, alloc_size)) |raw_buff| {
            errdefer kernel.mm.kfree(raw_buff);
            @memset(raw_buff[0..alloc_size], 0);
            sb.base.dev_file.?.pos = sb.base.block_size * block;
            var read: u32 = 0;
            while (read < alloc_size) {
                const single_read: u32 = try sb.base.dev_file.?.ops.read(
                    sb.base.dev_file.?,
                    @ptrCast(&raw_buff[read]),
                    sb.base.block_size
                );
                // FIXME:
                if (single_read == 0) break;
                read += single_read;
            }
            return raw_buff[0..alloc_size];
        } else {
            kernel.logger.INFO("Ext2: Allocate buffer: Out of Memory", .{});
            return kernel.errors.PosixError.ENOMEM;
        }
    }

    pub fn writeBuff(sb: *Ext2Super, block: u32, buff: [*]const u8, size: u32) !u32 {
            var to_write: u32 = size;
            sb.base.dev_file.?.pos = sb.base.block_size * block;
            var written: u32 = 0;
            while (written < size) {
                const single_write: u32 = try sb.base.dev_file.?.ops.write(
                    sb.base.dev_file.?,
                    @ptrCast(&buff[written]),
                    to_write
                );
                sb.base.dev_file.?.pos += single_write;
                to_write -= single_write;
                if (single_write == 0) break;
                written += single_write;
            }
            return written;
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

    pub fn insertDirent(
        sb: *Ext2Super,
        parent: *Ext2Inode,
        child_ino: u32,
        name: []const u8,
        mode: fs.UMode,
    ) !void {
        const size = @sizeOf(Ext2DirEntry) + ((name.len + 3) & ~@as(u32, 3));

        var blk_idx: u32 = 0;
        while (blk_idx < parent.maxBlockIdx()) : (blk_idx += 1) {
            const pbn = parent.data.i_block[blk_idx];
            if (pbn == 0)
                break;

            const blk = try sb.readBlocks(pbn, 1);
            defer kernel.mm.kfree(blk.ptr);

            var off: u32 = 0;
            while (off < sb.base.block_size) {
                var de: *Ext2DirEntry = @ptrFromInt(@intFromPtr(blk.ptr) + off);
                if (de.rec_len == 0)
                    break;

                const used_size = @sizeOf(Ext2DirEntry) + ((de.name_len + 3) & ~@as(u32, 3));
                const spare = @as(u32, de.rec_len) - used_size;
                if (spare >= size) {
                    // shrink current
                    de.rec_len = @intCast(used_size);

                    // new entry
                    var nde: *Ext2DirEntry = @ptrFromInt(@intFromPtr(de) + used_size);
                    nde.inode = child_ino;
                    nde.name_len = @intCast(name.len);
                    nde.rec_len = @intCast(spare);
                    nde.setFileType(mode);
                    const nstart: [*]u8 = @ptrFromInt(@intFromPtr(nde) + @sizeOf(Ext2DirEntry));
                    @memcpy(nstart[0..name.len], name);

                    // write back
                    _ = try sb.writeBuff(pbn, blk.ptr, sb.base.block_size);
                    return;
                }
                off += de.rec_len;
            }
        }
        // TO DO: alloc new block
    }

};

const ext2_super_ops = fs.SuperOps{
    .alloc_inode = Ext2Super.allocInode,
};
