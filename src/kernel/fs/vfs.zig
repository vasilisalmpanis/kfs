const kernel = @import("../main.zig");
const TreeNode = @import("../utils/tree.zig").TreeNode;
const mount = @import("mount.zig");
const Refcount = @import("../sched/task.zig").RefCount;
const lst = @import("../utils/list.zig");
const fs = @import("./fs-type.zig");
const std = @import("std");

// pub const Inode = struct {
//     ops: *InodeOps,
//     ref: Refcount,
// };
//

// SuperBlock: Is the representation of a mounted filesystem.
// it containes metadata about the filesystem, root inode
// and it is responsible for the creation of new inodes(?).

// Mount: Represents a mountpoint where a filesystem is mounted.
// it maps a superblock to a specific dentry outside of this filesystem.

// Inode: Represents an object in the filesystem.
// only one copy of a specific inode exists at every point
// in time but each inode can have multiple dentries.

// Dentry: the path representation of every inode on the filesystem
// (RF, BD, CD, sockets, pipes, etc). There can be multiple different dentries
// that point to the same underlying inode.

// File: it represents any currently open inode in the current process.

pub const DEntry = struct {
    sb: *SuperBlock,
    // inode: *Inode,
    ref: Refcount,
    name: []u8,
    tree: TreeNode,

    pub fn drop(self: *Refcount) void {
        const dentry: *DEntry = lst.containerOf(DEntry, @intFromPtr(self), "ref");
        kernel.mm.kfree(dentry);
    }

    pub fn alloc(name: []const u8, sb: *SuperBlock) !*DEntry {
        if (kernel.mm.kmalloc(DEntry)) |entry| {
            if (kernel.mm.kmallocArray(u8, name.len)) |nm| {
                @memcpy(nm[0..name.len], name[0..name.len]);
                entry.name = nm[0..name.len];
            } else {
                return error.OutOfMemory;
            }
            entry.sb = sb;
            entry.ref = Refcount.init();
            entry.ref.dropFn = drop;
            entry.tree.setup();
            return entry;
        }
        return error.OutOfMemory;
    }

    pub fn release(self: *DEntry) void {
        self.ref.unref();
    }
};

pub const SuperBlock = struct {
    // ops: *SuperOps,
    root: *DEntry,
    fs: *fs.FileSystem,
    ref: Refcount,
    list: lst.ListHead,

    
};

// pub const File = struct {
//     ops: *FileOps,
//     dentry: *DEntry,
//     vfsmount: *mount.VFSmount,
//     ref: Refcount,
// };
//
// pub const FileOps = struct {
//     ptr: *anyopaque,
//     vtable: *const VTable,
//
//     pub const VTable = struct {
//         open: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//         release: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//         read: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         write: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//     };
// };
//
// pub const InodeOps = struct {
//     ptr: *anyopaque,
//     vtable: *const VTable,
//
//     pub const VTable = struct {
//         lookup: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//         readlink: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//         create: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // link: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // unlink: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // symlink: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // mkdir: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // rmdir: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // rename: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // setattr: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         // getattr: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//     };
// };
//
// pub const SuperOps = struct {
//     ptr: *anyopaque,
//     vtable: *const VTable,
//
//     pub const VTable = struct {
//         alloc_inode: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//         destroy_inode: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//         free_inode: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//         shutdown: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//     };
// };

pub var last_ino: u32 = 0;
var last_ino_lock = kernel.Mutex.init();

pub fn get_ino() u32 {
    last_ino_lock.lock();
    defer last_ino_lock.unlock();
    const tmp = last_ino;
    last_ino += 1;
    return tmp;
}

pub const UMode = struct {
    grp: u4 = 0,
    usr: u4 = 0,
    other: u4 = 0,
    _unsed: u4 = 0
};

pub const Inode = struct {
    i_no: u32 = 0,
    sb: *SuperBlock,
    ref: Refcount = Refcount.init(),
    mode: UMode = UMode{},
    is_dirty: bool = false,
    size: u32 = 0,

    pub fn alloc() !*Inode {
        if (kernel.mm.kmalloc(Inode)) |node| {
            // node.setup(null);
            return node;
        }
        return error.OutOfMemory;
    }

    pub fn setup(
        self: *Inode,
        sb: *SuperBlock,
    ) void {
        self.i_no = get_ino();
        self.sb = sb;
        self.ref = Refcount.init();
        self.size = 0;
        self.mode = UMode{};
        self.is_dirty = false;
    }
};
