const std = @import("std");
const krn = @import("kernel");
const dev = @import("./device.zig");
const drivers = @import("./main.zig");

var bdev_map: std.AutoHashMap(dev.dev_t, *dev.Device) = undefined;
var bdev_map_mtx = krn.Mutex.init();

pub fn init() void {
    bdev_map = std.AutoHashMap(dev.dev_t, *dev.Device).init(krn.mm.kernel_allocator.allocator());
}

const disk_names = std.StaticBitSet(26);

fn bdev_open(base: *krn.fs.File, inode: *krn.fs.Inode) !void {
    if (inode.dev == null) inode.dev = try getbdev(inode.dev_id);
    if (inode.dev) |_dev| {
        if (_dev.driver) |drv| {
            if (drv.fops) |ops| {
                base.ops = ops;
                krn.logger.INFO("replacing\n", .{});
                return try base.ops.open(base, inode);
            }
            return krn.errors.PosixError.ENXIO;
        }
        return krn.errors.PosixError.ENOENT;
    }
}

fn bdev_close(base: *krn.fs.File) void {
    _ = base;
}

fn bdev_write(base: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

fn bdev_read(base: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

pub const bdev_default_ops: krn.fs.FileOps = .{
    .open = bdev_open,
    .close = bdev_close,
    .read = bdev_read,
    .write = bdev_write,
    .lseek = null,
};

pub fn addbdev(device: *dev.Device) !void {
    // if (!device.id.valid()) {
    //     return krn.errors.PosixError.ENOENT;
    // }
    bdev_map_mtx.lock();
    defer bdev_map_mtx.unlock();

    try bdev_map.put(device.id, device);
    if (drivers.devfs_path.dentry.inode.ops.mknod) |_mknod| {
        const mode  = krn.fs.UMode{
            .type = krn.fs.S_IFBLK,
            .usr = 0o6,
            .grp = 0o6,
            .other = 0o6,
        };
        _ = _mknod(drivers.devfs_path.dentry.inode,
            device.name,
            mode,
            drivers.devfs_path.dentry,
            device.id
        ) catch {
        };
    }
}

pub fn getbdev(devt: dev.dev_t) !*dev.Device {
    bdev_map_mtx.lock();
    defer bdev_map_mtx.unlock();

    if (bdev_map.get(devt)) |_dev| {
        return _dev;
    }
    return krn.errors.PosixError.ENOENT;
}
