const inode = @import("inode.zig");
const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");
const std = @import("std");

pub fn mkdir(parent: *fs.DEntry, name: []const u8) !*fs.DEntry {
    const mode = kernel.fs.UMode{
        .usr = 5,
        .grp = 5,
        .other = 5,
        .type = fs.S_IFDIR,
    };
    return try parent.inode.ops.mkdir(parent.inode, parent, name, mode);
}

pub fn createFile(parent: *fs.DEntry, name: []const u8, fops: *const fs.FileOps, mode: fs.UMode) !*fs.DEntry {
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
                    try callback(child, dentry);
                }
            } else {
                if (child.inode.ops.unlink) |callback| {
                    try callback(child);
                }
            }
        }
    }
    if (dentry.inode.ops.rmdir) |callback| {
        if (dentry.tree.parent) |node| {
            const parent: *fs.DEntry = node.entry(fs.DEntry, "tree");
            try callback(dentry, parent);
        }
    }
}

pub fn deleteProcess(task: *kernel.task.Task) void {
    var buff: [5]u8 = .{0} ** 5;
    const slice = std.fmt.bufPrint(buff[0..5], "{d}", .{task.pid}) catch { return; };
    const dentry = fs.procfs.root.inode.ops.lookup(fs.procfs.root, slice) catch {
        @panic("Not found? This shouldn't happen\n");
    };
    _ = deleteRecursive(dentry) catch {};

}

fn stat_open(_: *kernel.fs.File, base: *kernel.fs.Inode) !void {
    const proc_inode = base.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        return kernel.errors.PosixError.EINVAL;
    };
    task.refcount.ref();
}

fn stat_close(file: *kernel.fs.File) void {
    const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        @panic("Should not happen");
    };
    task.refcount.unref();
}

fn stat_read(file: *kernel.fs.File, buff: [*]u8, size: u32) !u32 {
    const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        @panic("Should not happen");
    };
    var buffer: [256]u8 = .{0} ** 256;
    const string = try std.fmt.bufPrint(buffer[0..256],
        "{d} ({s}) S 2 0 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 14 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0",
        .{
            task.pid,
            std.mem.span(@as([*:0]u8, @ptrCast(&task.name))),
        }
    );
    kernel.logger.INFO("slice {s} len {d}\n", .{string, string.len});
    var to_read: u32 = size;
    if (file.pos >= string.len)
        return 0;
    if (file.pos + to_read >= string.len)
        to_read = string.len - file.pos;
    @memcpy(buff[0..to_read], string[file.pos..file.pos + to_read]);
    file.pos += to_read;
    return to_read;
}

fn stat_write(_: *kernel.fs.File, _: [*]const u8, _: u32) !u32 {
    return kernel.errors.PosixError.ENOSYS;
}

const file_ops = fs.FileOps{
    .open = stat_open,
    .read = stat_read,
    .write = stat_write,
    .close = stat_close,
};


pub fn newProcess(task: *kernel.task.Task) !void {
    var buff: [5]u8 = .{0} ** 5;
    const slice = try std.fmt.bufPrint(buff[0..5], "{d}", .{task.pid});
    const parent = try kernel.fs.procfs.mkdir(kernel.fs.procfs.root, slice);
    const mode = kernel.fs.UMode{
        .usr = 4,
        .grp = 4,
        .other = 4,
        .type = fs.S_IFREG,
    };
    const child = try createFile(parent,
        "stat",
        &file_ops,
        mode
    );
    const proc_inode: *inode.ProcInode = child.inode.getImpl(inode.ProcInode, "base");
    proc_inode.task = task;
}
