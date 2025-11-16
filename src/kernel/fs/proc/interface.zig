const inode = @import("inode.zig");
const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");
const std = @import("std");

pub fn mkdir(parent: *fs.DEntry, name: []const u8) !*fs.DEntry {
    const mode = kernel.fs.UMode.directory();
    return try parent.inode.ops.mkdir(parent.inode, parent, name, mode);
}

pub fn createFile(
    parent: *fs.DEntry,
    name: []const u8,
    fops: *const fs.FileOps,
    mode: fs.UMode
) !*fs.DEntry {
    _ = parent.inode.ops.lookup(parent, name) catch {
        const new_file = try parent.inode.ops.create(parent.inode, name, mode, parent);
        new_file.inode.fops = fops;
        return new_file;
    };
    return kernel.errors.PosixError.EEXIST;
}

pub fn deleteRecursive(dentry: *fs.DEntry) !void {
    if (dentry.tree.hasChildren()) {
        var it = dentry.tree.child.?.siblingsIterator();
        while (it.next()) |node| {
            const child = node.curr.entry(fs.DEntry, "tree");
            if (child.inode.mode.isDir()) {
                try deleteRecursive(child);
                if (child.inode.ops.rmdir) |callback| {
                    it.reset(node.curr);
                    try callback(child, dentry);
                    child.release();
                }
            } else {
                if (child.inode.ops.unlink) |callback| {
                    it.reset(node.curr);
                    try callback(dentry.inode, child);
                    child.release();
                }
            }
        }
    }
    if (dentry.inode.ops.rmdir) |callback| {
        if (dentry.tree.parent) |node| {
            const parent: *fs.DEntry = node.entry(fs.DEntry, "tree");
            try callback(dentry, parent);
            parent.release();
        }
    }
}
