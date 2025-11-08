const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");
const interface = @import("interface.zig");
const std = @import("std");

const mounts_ops = kernel.fs.FileOps{
    .open = mounts_open,
    .read = mounts_read,
    .write = mounts_write,
    .close = mounts_close,
};

const Slice = struct {
    ptr: *anyopaque,
    len: u32,
};

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
        const slice = kernel.mm.kmalloc(Slice) orelse {
            return kernel.errors.PosixError.ENOMEM;
        };
        slice.ptr = content.ptr;
        slice.len = content.len;
        base.data = slice;
    }
}

fn mounts_close(base: *kernel.fs.File) void {
    if (base.data == null)
        return ;
    const slice: *Slice = @ptrCast(@alignCast(base.data));
    kernel.mm.kfree(slice.ptr);
    kernel.mm.kfree(base.data.?);
}

fn mounts_write(_: *kernel.fs.File, _: [*]const u8, _: u32) anyerror!u32 {
    return kernel.errors.PosixError.ENOSYS;
}

fn mounts_read(base: *kernel.fs.File, buf: [*]u8, size: u32) anyerror!u32 {
    if (base.data == null)
        return 0;

    const content: *[]const u8 = @ptrCast(@alignCast(base.data));
    var to_read: u32 = size;
    if (base.pos >= content.len)
        return 0;
    if (base.pos + to_read > content.len) {
        to_read = content.len - base.pos;
    }
    @memcpy(buf[0..to_read], content.*[base.pos..base.pos + to_read]);
    base.pos += to_read;
    return to_read;
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
}
