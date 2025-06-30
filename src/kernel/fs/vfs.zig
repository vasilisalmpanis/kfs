const kernel = @import("../../main.zig");
const TreeNode = @import("../utils/tree.zig").TreeNode;
const mount = @import("mount.zig");
const Refcount = @import("../sched/task.zig").RefCount;

pub const Inode = struct {
    ops: *InodeOps,
    ref: Refcount,
};

pub const DEntry = struct {
    sb: *SuperBlock,
    inode: *Inode,
    ref: Refcount,
    name: []u8,
    tree: TreeNode,

};

pub const SuperBlock = struct {
    ops: *SuperOps,
};

pub const File = struct {
    ops: *FileOps,
    dentry: *DEntry,
    vfsmount: *mount.VFSmount,
    ref: Refcount,
};

pub const FileOps = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        open: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        release: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
        read: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        write: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
    };
};

pub const InodeOps = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        lookup: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        readlink: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
        create: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // link: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // unlink: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // symlink: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // mkdir: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // rmdir: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // rename: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // setattr: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // getattr: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
    };
};

pub const SuperOps = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        alloc_inode: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        destroy_inode: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
        free_inode: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        shutdown: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
    };
};
