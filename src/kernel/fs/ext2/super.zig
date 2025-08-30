const fs = @import("../fs.zig");
const kernel = fs.kernel;
const Ext2Inode = @import("inode.zig").Ext2Inode;
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
	s_mnt_count			:u16,	// Mount count
	s_max_mnt_count 		:i16,	// Maximal mount count
	s_magic		        	:u16,	// Magic signature
	s_state		        	:u16,	// File system state
	s_errors			:u16,	// Behaviour when detecting errors
	s_minor_rev_level 		:u16,	// minor revision level
	s_lastcheck			:u32,	// time of last check
	s_checkinterval	        	:u32,	// max. time between checks
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
	s_first_ino 		:u32,           // First non-reserved inode */
	s_inode_size 		:u16,           // size of inode structure */
	s_block_group_nr 	:u16,           // block group # of this superblock */
	s_feature_compat 	:u32,           // compatible feature set */
	s_feature_incompat 	:u32,           // incompatible feature set */
	s_feature_ro_compat 	:u32,           // readonly-compatible feature set */
	s_reserved	        :[230] u32,     // Padding to the end of the block */
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
            var number_of_block_groups: u32 = ext2_super_data.s_blocks_count / ext2_super_data.s_blocks_per_group;
            if (ext2_super_data.s_blocks_count % ext2_super_data.s_blocks_per_group != 0)
                number_of_block_groups += 1;
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
            sb.base.inode_map.put(root_inode.i_no, root_inode) catch |err| {
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

    pub fn getFirstInodeIdx(self: *Ext2Super) u32 {
        if (self.data.s_rev_level == 0) {
            return 11;
        } else {
            return self.data.s_first_ino;
        }
    }
};

const ext2_super_ops = fs.SuperOps{
    .alloc_inode = Ext2Super.allocInode,
};
