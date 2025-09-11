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
    if (inode.dev == null) inode.dev = try getBdev(inode.dev_id);
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

fn bdev_write(base: *krn.fs.File, buf: [*]const u8, size: u32) !u32 {
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
    .readdir = null,
};

pub fn addBdev(device: *dev.Device) !void {
    if (bdev_map.get((device.id))) |_d| {
        krn.logger.ERROR(
            "Bdev with id {d}:{d} already exists: {s}\n",
            .{device.id.major, device.id.minor, _d.name}
        );
        return krn.errors.PosixError.EEXIST;
    }

    if (drivers.devfs_path.dentry.inode.ops.mknod) |_mknod| {
        bdev_map_mtx.lock();
        defer bdev_map_mtx.unlock();

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
        ) catch |err| {
            krn.logger.ERROR("mknod failed: {t}", .{err});
            return err;
        };
        try bdev_map.put(device.id, device);
    } else {
        krn.logger.ERROR(
            "No mknod operation in {s}\n", 
            .{drivers.devfs_path.dentry.inode.sb.fs.name}
        );
        return krn.errors.PosixError.ENOSYS;
    }
}

pub fn getBdev(devt: dev.dev_t) !*dev.Device {
    bdev_map_mtx.lock();
    defer bdev_map_mtx.unlock();

    if (bdev_map.get(devt)) |_dev| {
        return _dev;
    }
    return krn.errors.PosixError.ENOENT;
}
