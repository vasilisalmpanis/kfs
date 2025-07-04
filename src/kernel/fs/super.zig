const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const Refcount = fs.Refcount;
const list = fs.list;

/// SuperBlock: Is the representation of a mounted filesystem.
/// it containes metadata about the filesystem, root inode
/// and it is responsible for the creation of new inodes(?).

pub const SuperBlock = struct {
    // ops: *SuperOps,
    root: *DEntry,
    fs: *fs.FileSystem,
    ref: Refcount,
    list: list.ListHead,

    
};

// TODO: define the SuperOps callbacks and document them
// pub const SuperOps = struct {
//    alloc_inode: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//    destroy_inode: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//    free_inode: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//    shutdown: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
// };

