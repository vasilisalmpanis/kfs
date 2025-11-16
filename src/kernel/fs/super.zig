const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const Refcount = fs.Refcount;
const list = fs.list;
const std = @import("std");
const krn = @import("../main.zig");
const drv = @import("driver");

/// SuperBlock: Is the representation of a mounted filesystem.
/// it containes metadata about the filesystem, root inode
/// and it is responsible for the creation of new inodes(?).

pub const SuperBlock = struct {
    ops: *const SuperOps,
    root: *DEntry,
    fs: *fs.FileSystem,
    ref: Refcount,
    list: list.ListHead,
    block_size: u32,
    inode_map: std.AutoHashMap(u32, *fs.Inode),
    dev_file: ?*fs.File = null,
    magic: u32,
    
    pub fn getImpl(base: *SuperBlock, comptime T: type, comptime member: []const u8) *T {
        return @fieldParentPtr(member, base);
    }
};

pub const Statfs = extern struct {
	type: u32,
	bsize: u32,
	blocks: u32 = 0,
	bfree: u32 = 0,
	bavail: u32 = 0,
	files: u32 = 0,
	ffree: u32 = 0,
	fsid: u32,
	namelen: u64,
	frsize: u32 = 0,
	flags: u32 = 0,
};

// TODO: define the SuperOps callbacks and document them
pub const SuperOps = struct {
    // responsible of allocating a concrete inode type
    alloc_inode: *const fn (base: *SuperBlock) anyerror!*fs.Inode,
    destroy_inode: ?*const fn (base: *SuperBlock, base: *fs.Inode) anyerror!void = null,
    statfs: ?*const fn (base: *SuperBlock) anyerror!Statfs = vfs_statfs,
};

fn vfs_statfs(base: *SuperBlock) !Statfs {
    return Statfs{
        .type = base.magic,
        .bsize = krn.mm.PAGE_SIZE,
        .namelen = 255,
        .fsid = 0,
    };
}
