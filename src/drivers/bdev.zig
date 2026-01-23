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
    if (inode.data.dev == null) inode.data.dev = try getBdev(inode.dev_id);
    if (inode.data.dev) |_dev| {
        if (_dev.driver) |drv| {
            if (drv.fops) |ops| {
                base.ops = ops;
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

fn bdev_write(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

fn bdev_read(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
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
    .readdir = null,
};

pub fn addDevFile(mode: krn.fs.UMode, name: []const u8, device: *dev.Device) !void {
    if (drivers.devfs_path.dentry.inode.ops.mknod) |_mknod| {
        var new_mode  = mode;
        new_mode.type = krn.fs.S_IFBLK;
        _ = _mknod(drivers.devfs_path.dentry.inode,
            name,
            new_mode,
            drivers.devfs_path.dentry,
            device.id
        ) catch |err| {
            krn.logger.ERROR("mknod failed: {t}", .{err});
            return err;
        };
    } else {
        krn.logger.ERROR(
            "No mknod operation in {s}\n", 
            .{drivers.devfs_path.dentry.inode.sb.?.fs.name}
        );
        return krn.errors.PosixError.ENOSYS;
    }
}

pub fn addBdev(device: *dev.Device, mode: krn.fs.UMode) !void {
    if (bdev_map.get((device.id))) |_d| {
        krn.logger.ERROR(
            "Bdev with id {d}:{d} already exists: {s}\n",
            .{device.id.major, device.id.minor, _d.name}
        );
        return krn.errors.PosixError.EEXIST;
    }
    bdev_map_mtx.lock();
    defer bdev_map_mtx.unlock();

    try addDevFile(mode, device.name, device);
    try bdev_map.put(device.id, device);
}

pub fn getBdev(devt: dev.dev_t) !*dev.Device {
    bdev_map_mtx.lock();
    defer bdev_map_mtx.unlock();

    if (bdev_map.get(devt)) |_dev| {
        return _dev;
    }
    return krn.errors.PosixError.ENOENT;
}
