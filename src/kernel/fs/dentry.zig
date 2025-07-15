const fs = @import("fs.zig");
const SuperBlock = fs.SuperBlock;
const Refcount = fs.Refcount;
const TreeNode = fs.TreeNode;
const kernel = fs.kernel;
const list = fs.list;
const std = @import("std");

/// Dentry: the path representation of every inode on the filesystem
/// (RF, BD, CD, sockets, pipes, etc). There can be multiple different dentries
/// that point to the same underlying inode.
///
pub fn init_cache(allocator: std.mem.Allocator) void {
    cache = std.StringHashMap(*DEntry).init(allocator);
    fs.dcache = std.HashMap(
        fs.DentryHash,
        *fs.DEntry,
        fs.InoNameContext,
        50,
    ).init(allocator);
}

pub var cache: std.StringHashMap(*DEntry) = undefined;

pub const DEntry = struct {
    sb: *SuperBlock,
    inode: *fs.Inode,
    ref: Refcount,
    name: []u8,
    tree: TreeNode,

    pub fn drop(self: *Refcount) void {
        const dentry: *DEntry = list.containerOf(DEntry, @intFromPtr(self), "ref");
        dentry.tree.del();
        kernel.mm.kfree(dentry);
    }

    pub fn alloc(name: []const u8, sb: *SuperBlock, ino: *fs.Inode) !*DEntry {
        if (kernel.mm.kmalloc(DEntry)) |entry| {
            if (kernel.mm.kmallocArray(u8, name.len)) |nm| {
                @memcpy(nm[0..name.len], name[0..name.len]);
                entry.name = nm[0..name.len];
            } else {
                return error.OutOfMemory;
            }
            entry.sb = sb;
            entry.ref = Refcount.init();
            entry.ref.ref();
            entry.ref.dropFn = drop;
            entry.tree.setup();
            entry.inode = ino;
            return entry;
        }
        return error.OutOfMemory;
    }

    pub fn release(self: *DEntry) void {
        self.ref.unref();
        kernel.mm.kfree(self.name.ptr);
    }
};

