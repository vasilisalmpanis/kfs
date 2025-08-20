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
    if (inode.dev == null) inode.dev = try getCdev(inode.dev_id);
    if (inode.dev) |_dev| {
        if (_dev.driver) |drv| {
            if (drv.fops) |ops| {
                base.ops = ops;
                return ;
            }
            return krn.errors.PosixError.ENXIO;
        }
    }
}

fn cdev_close(base: *krn.fs.File) void {
    _ = base;
}

fn cdev_write(base: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

fn cdev_read(base: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
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
};

pub fn addCdev(device: *dev.Device) !void {
    if (!device.id.valid()) {
        return krn.errors.PosixError.ENOENT;
    }
    cdev_map_mtx.lock();
    defer cdev_map_mtx.unlock();

    try cdev_map.put(device.id, device);
    if (drivers.devfs_path.dentry.inode.ops.mknod) |function| {
        const mode  = krn.fs.UMode{
            .type = krn.fs.S_IFCHR,
            .usr = 0o6,
            .grp = 0o6,
            .other = 0o6,
        };
        _ = function(drivers.devfs_path.dentry.inode,
            device.name,
            mode,
            drivers.devfs_path.dentry,
            device.id
        ) catch {
        };
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
