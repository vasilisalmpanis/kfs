const std = @import("std");
const krn = @import("kernel");
const dev = @import("./device.zig");
const drivers = @import("./main.zig");

var cdev_map: std.AutoHashMap(dev.dev_t, *dev.Device) = undefined;
var cdev_map_mtx = krn.Mutex.init();

pub fn init() void {
    cdev_map = std.AutoHashMap(dev.dev_t, *dev.Device).init(krn.mm.kernel_allocator.allocator());
}

fn cdev_open(base: *krn.fs.File, inode: *krn.fs.Inode) !void {
    krn.logger.WARN("dev file opened\n",.{});
    if (inode.data.dev == null) inode.data.dev = try getCdev(inode.dev_id);
    if (inode.data.dev) |_dev| {
        if (_dev.driver) |drv| {
            if (drv.fops) |ops| {
                base.ops = ops;
                return try base.ops.open(base, inode);
            }
            return krn.errors.PosixError.ENXIO;
        }
    }
}

fn cdev_close(base: *krn.fs.File) void {
    _ = base;
}

fn cdev_write(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

fn cdev_read(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

pub const cdev_default_ops: krn.fs.FileOps = .{
    .open = cdev_open,
    .close = cdev_close,
    .read = cdev_read,
    .write = cdev_write,
    .lseek = null,
    .readdir = null,
};

pub fn addCdev(device: *dev.Device, mode: krn.fs.UMode, path: ?[]const u8) !void {
    if (cdev_map.get(device.id)) |_d| {
        krn.logger.ERROR(
            "Cdev with id {d}:{d} already exists: {s}\n",
            .{device.id.major, device.id.minor, _d.name}
        );
        return krn.errors.PosixError.EEXIST;
    }

    const dir_path = if (path != null)
        try krn.fs.path.resolve(path.?)
    else
        drivers.devfs_path;
    defer if (path != null) dir_path.release();
    if (dir_path.dentry.inode.ops.mknod) |_mknod| {
        cdev_map_mtx.lock();
        defer cdev_map_mtx.unlock();

        var new_mode  = mode;
        new_mode.type = krn.fs.S_IFCHR;
        _ = _mknod(dir_path.dentry.inode,
            device.name,
            new_mode,
            dir_path.dentry,
            device.id
        ) catch |err| {
            krn.logger.ERROR("mknod failed: {t}", .{err});
            return err;
        };
        try cdev_map.put(device.id, device);
    } else {
        krn.logger.ERROR(
            "No mknod operation in {s}\n",
            .{dir_path.dentry.inode.sb.?.fs.name}
        );
        return krn.errors.PosixError.ENOSYS;
    }
}

pub fn getCdev(devt: dev.dev_t) !*dev.Device {
    cdev_map_mtx.lock();
    defer cdev_map_mtx.unlock();

    if (cdev_map.get(devt)) |_dev| {
        return _dev;
    }
    return krn.errors.PosixError.ENOENT;
}

pub fn rmCdev(devt: dev.dev_t) !void {
    cdev_map_mtx.lock();
    defer cdev_map_mtx.unlock();

    if (cdev_map.get(devt)) |_dev| {
        const _d = try drivers.devfs_path.dentry.inode.ops.lookup(
            drivers.devfs_path.dentry,
            _dev.name
        );
        _d.release();
        if (_d.inode.ops.unlink) |_unlink| {
            try _unlink(drivers.devfs_path.dentry.inode, _d);
        }
        _ = cdev_map.remove(devt);
        return ;
    }
    return krn.errors.PosixError.ENOENT;
}
