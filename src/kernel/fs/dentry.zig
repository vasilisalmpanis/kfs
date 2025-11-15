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
        99,
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
        kernel.logger.WARN("Dropping {s}\n", .{dentry.name});
        if (dentry.tree.parent) |_p| {
            const _parent = _p.entry(fs.DEntry, "tree");
            const key = fs.DentryHash{
                .sb = @intFromPtr(dentry.sb),
                .ino = _parent.inode.i_no,
                .name = dentry.name
            };
            _ = fs.dcache.remove(key);
            _ = dentry.sb.inode_map.remove(dentry.inode.i_no);
            _parent.ref.unref();
        }
        kernel.mm.kfree(dentry.name.ptr);
        dentry.tree.del();
        kernel.mm.kfree(dentry);
    }

    pub fn alloc(name: []const u8, sb: *SuperBlock, ino: *fs.Inode) !*DEntry {
        if (kernel.mm.kmalloc(DEntry)) |entry| {
            if (kernel.mm.dupSlice(u8, name)) |nm| {
                entry.name = nm;
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

    pub fn new(parent: *DEntry, name: []const u8, ino: *fs.Inode) !*DEntry {
        parent.ref.ref();
        errdefer parent.ref.unref();
        if (ino.sb == null)
            return kernel.errors.PosixError.EINVAL;
        const new_dentry: *fs.DEntry = fs.DEntry.alloc(name, ino.sb.?, ino) catch {
            return kernel.errors.PosixError.ENOMEM;
        };
        parent.tree.addChild(&new_dentry.tree);
        fs.dcache.put(
            fs.DentryHash{
                .sb = @intFromPtr(parent.sb),
                .ino = parent.inode.i_no,
                .name = new_dentry.name,
            },
            new_dentry
        ) catch {
            new_dentry.tree.del();
            kernel.mm.kfree(new_dentry);
            return kernel.errors.PosixError.ENOMEM;
        };
        return new_dentry;
    }

    pub fn release(self: *DEntry) void {
        self.ref.unref();
    }
};

