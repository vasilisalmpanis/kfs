const krn = @import("../main.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const errors = @import("error-codes.zig").PosixError;
const std = @import("std");
const dbg = @import("debug");


pub fn do_mount(
    dev_name: []const u8,
    dir_name: []const u8,
    fs_type: []const u8,
    _: u32,
    _: ?*anyopaque
) !u32 {
    if (fs.FileSystem.find(fs_type)) |_type| {
        _ = fs.Mount.mount(dev_name, dir_name, _type) catch |err| {
            krn.logger.ERROR(
                "Error while mounting {s} dev {s} to {s}: {any} \n",
                .{fs_type, dev_name, dir_name, err}
            );
            return errors.ENOENT;
        };
        krn.logger.DEBUG(
            "mounted successfuly {s} dev {s} to {s}",
            .{fs_type, dev_name, dir_name}
        );
        return 0;
    }
    return errors.ENOENT;
}

pub fn mount(
    dev_name: ?[*:0]const u8,
    dir_name: ?[*:0]const u8,
    fs_type: ?[*:0]const u8,
    new_flags: u32,
    data: ?*anyopaque
) !u32 {
    if (dev_name == null or dir_name == null or fs_type == null) {
        return errors.EINVAL;
    }
    const _dev: []const u8 = std.mem.span(dev_name.?);
    const _dir: []const u8 = std.mem.span(dir_name.?);
    const _fs: []const u8 = std.mem.span(fs_type.?);
    // TO DO: copy above values from userspace to kernelspace

    krn.logger.DEBUG("sys mount {s} {s} {s} {x}", .{_dev, _dir, _fs, new_flags});
    return try do_mount(_dev, _dir, _fs, new_flags, data);
}

pub fn do_umount(
    name: []const u8,
) !u32 {
    const path = try krn.fs.path.resolve(name); // /ext2
    defer path.release();
    if (path.isRoot()) {
        if (path.mnt.tree.hasChildren() or path.mnt.count.getValue() > 2) {
            return errors.EBUSY;
        }
        const mountpoint: *fs.Mount = path.mnt;
        mountpoint.remove(); // Removed from tree. Now we can free all the children.
        mountpoint.sb.ref.unref();
        return 0;
    } else  {
        krn.logger.INFO("{s}: not a mountpoint!", .{name});
    }
    return errors.EINVAL;
}

pub fn umount(
    name: ?[*:0]u8,
) !u32 {
    if (name) |_name| {
        const target: []const u8 = std.mem.span(_name);
        if (target.len == 0) {
            return errors.EINVAL;
        }
        return try do_umount(target);
    }
    return errors.EFAULT;
}
