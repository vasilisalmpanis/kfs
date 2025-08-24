const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const utils = @import("kernel").list;
const std = @import("std");
const kernel = @import("kernel");
const StorageDevice = @import("./device.zig").StorageDevice;
const bus = @import("./bus.zig");

pub const StorageDriver = struct {
    driver: drv.Driver,

    probe: *const fn(*StorageDevice) anyerror!void,
    remove: *const fn(*StorageDevice) anyerror!void,
};

// core probe wrapper
fn storage_probe_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const storage_dev: *StorageDevice = @fieldParentPtr("dev", device);
    const storage_driver: *StorageDriver = @fieldParentPtr("driver", driver);

    try storage_driver.probe(storage_dev);
}

fn storage_remove_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const storage_dev: *StorageDevice = @fieldParentPtr("dev", device);
    const storage_driver: *StorageDriver = @fieldParentPtr("driver", driver);

    try storage_driver.remove(storage_dev);
}

pub fn storage_register_driver(driver: *drv.Driver) !void {
    driver.probe = storage_probe_device;
    driver.remove = storage_remove_device;
    try driver.register(&bus.storage_bus);
}

pub fn storage_unregister_driver(driver: *drv.Driver) void {
    driver.unregister(&bus.storage_bus);
}
