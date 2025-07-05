const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const Refcount = fs.Refcount;
const list = fs.list;
const std = @import("std");

/// SuperBlock: Is the representation of a mounted filesystem.
/// it containes metadata about the filesystem, root inode
/// and it is responsible for the creation of new inodes(?).

pub const SuperBlock = struct {
    ops: *SuperOps,
    root: *DEntry,
    fs: *fs.FileSystem,
    ref: Refcount,
    list: list.ListHead,
    inode_map: std.AutoHashMap(u32, *fs.Inode),
    
    pub fn getImpl(base: *SuperBlock, comptime T: type, comptime member: []const u8) *T {
        return @fieldParentPtr(member, base);
    }
};

// TODO: define the SuperOps callbacks and document them
pub const SuperOps = struct {
    // responsible of allocating a concrete inode type
    alloc_inode: *const fn (base: *SuperBlock) anyerror!*fs.Inode,
};

