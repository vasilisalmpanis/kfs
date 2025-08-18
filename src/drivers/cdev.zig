const std = @import("std");
const krn = @import("kernel");
const dev = @import("./device.zig");

var cdev_map: std.AutoHashMap(dev.dev_t, *dev.Device) = undefined;
var cdev_map_mtx = krn.Mutex.init();

pub fn init() void {
    cdev_map = std.AutoHashMap(dev.dev_t, *dev.Device).init(krn.mm.kernel_allocator.allocator());
}

pub fn addCdev(device: *dev.Device) !void {
    if (!device.id.valid()) {
        return krn.errors.PosixError.ENOENT;
    }
    cdev_map_mtx.lock();
    defer cdev_map_mtx.unlock();

    try cdev_map.put(device.id, device);
    
}

pub fn getCdev(devt: dev.dev_t) !*dev.Device {
    cdev_map_mtx.lock();
    defer cdev_map_mtx.unlock();

    if (cdev_map.get(devt)) |_dev| {
        return _dev;
    }
    return krn.errors.PosixError.ENOENT;
}
