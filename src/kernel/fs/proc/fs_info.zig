const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");
const interface = @import("interface.zig");
const std = @import("std");
const generic_ops = @import("generic_ops.zig");

const mounts_ops = kernel.fs.FileOps{
    .open = mounts_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

const filesystems_ops = kernel.fs.FileOps{
    .open = filesystems_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

// Mounts

//proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
fn mounts_open(base: *kernel.fs.File, _: *kernel.fs.Inode) anyerror!void {
    var path_buffer: [256]u8 = .{0} ** 256;
    fs.mount.mnt_lock.lock();
    defer fs.mount.mnt_lock.unlock();

    if (fs.mount.mountpoints == null)
        return ;
    var size: u32 = 0;

    if (fs.mount.mountpoints) |head| {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const mnt = node.curr.entry(fs.Mount, "list");
            const mnt_path = mnt.getPath();
            defer mnt_path.release();

            var abs_path: []const u8 = try mnt_path.getAbsPath(path_buffer[0..256]);
            if (abs_path.len == 0) {
                abs_path = "/";
            }
            const entry_size = std.fmt.count("{s} on {s} type {s} (rw)\n", .{mnt.source, abs_path, mnt.sb.fs.name});
            size += entry_size;
        }
        const content = kernel.mm.kmallocSlice(u8, size) orelse {
            return kernel.errors.PosixError.ENOMEM;
        };
        errdefer kernel.mm.kfree(content.ptr);
        it = head.list.iterator();
        var offset: u32 = 0;
        while (it.next()) |node| {
            const mnt = node.curr.entry(fs.Mount, "list");
            const mnt_path = mnt.getPath();
            defer mnt_path.release();

            var abs_path: []const u8 = try mnt_path.getAbsPath(path_buffer[0..256]);
            if (abs_path.len == 0) {
                abs_path = "/";
            }
            const entry_slice = try std.fmt.bufPrint(content[offset..], "{s} on {s} type {s} (rw)\n", .{mnt.source, abs_path, mnt.sb.fs.name});
            offset += entry_slice.len;
        }
        try generic_ops.assignSlice(base, content);
    }
}

// filesystems

fn filesystems_open(base: *kernel.fs.File, _: *kernel.fs.Inode) anyerror!void {
    fs.filesystem.filesystem_mutex.lock();
    defer fs.filesystem.filesystem_mutex.unlock();

    const fs_head = fs.filesystem.fs_list orelse {
        return ;
    };

    var it = fs_head.list.iterator();
    var size: u32 = 0;
    while (it.next()) |node| {
        const filesystem = node.curr.entry(fs.FileSystem, "list");
        size += std.fmt.count("{s}  {s}\n",
            .{
                if (filesystem.virtual) "nodev" else "     ",
                    filesystem.name,
            }
        );
    }
    const content = kernel.mm.kmallocSlice(u8, size) orelse {
        return kernel.errors.PosixError.ENOMEM;
    };
    errdefer kernel.mm.kfree(content.ptr);
    it = fs_head.list.iterator();
    var offset: u32 = 0;
    while (it.next()) |node| {
        const filesystem = node.curr.entry(fs.FileSystem, "list");

        const entry_slice = try std.fmt.bufPrint(content[offset..], "{s}  {s}\n",
            .{
                if (filesystem.virtual) "nodev" else "     ",
                    filesystem.name,
            }
        );
        offset += entry_slice.len;
    }
    try generic_ops.assignSlice(base, content);
}

pub fn init() !void {
    const mode = kernel.fs.UMode{
        .usr = 4,
        .grp = 4,
        .other = 4,
        .type = kernel.fs.S_IFREG,
    };
    _ = try interface.createFile(
        fs.procfs.root,
        "mounts",
        &mounts_ops,
        mode
    );
    _ = try interface.createFile(
        fs.procfs.root,
        "filesystems",
        &filesystems_ops,
        mode
    );
}
