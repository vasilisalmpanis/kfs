const fs = @import("../fs.zig");
const kernel = fs.kernel;
const Ext2Inode = @import("inode.zig").Ext2Inode;
const std = @import("std");



pub const Ext2Super = struct {
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
        base: fs.SuperBlock,
    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
        return error.NotImplemented;
    }

    pub fn create(_fs: *fs.FileSystem, source: []const u8) !*fs.SuperBlock {
        if (kernel.mm.kmalloc(Ext2Super)) |sb| {
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            const root_inode = Ext2Inode.new(&sb.base) catch |err| {
                kernel.mm.kfree(sb);
                return err;
            };
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
            _ = source;
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
};

const ext2_super_ops = fs.SuperOps{
    .alloc_inode = Ext2Super.allocInode,
};
