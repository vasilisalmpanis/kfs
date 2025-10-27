const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const utils = @import("kernel").list;
const std = @import("std");
const kernel = @import("kernel");
const PlatformDevice = @import("./device.zig").PlatformDevice;
const bus = @import("./bus.zig");

pub const PlatformDriver = struct {
    driver: drv.Driver,

    probe: *const fn(*PlatformDevice) anyerror!void,
    remove: *const fn(*PlatformDevice) anyerror!void,
};

// core probe wrapper
fn platform_probe_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const platform_dev: *PlatformDevice = @fieldParentPtr("dev", device);
    const platform_driver: *PlatformDriver = @fieldParentPtr("driver", driver);

    try platform_driver.probe(platform_dev);
}

fn platform_remove_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const platform_dev: *PlatformDevice = @fieldParentPtr("dev", device);
    const platform_driver: *PlatformDriver = @fieldParentPtr("driver", driver);

    try platform_driver.remove(platform_dev);
}

pub fn platform_register_driver(driver: *drv.Driver) !void {
    driver.probe = platform_probe_device;
    driver.remove = platform_remove_device;
    try driver.register(&bus.platform_bus);
}

pub fn platform_unregister_driver(driver: *drv.Driver) !void {
    try driver.unregister(&bus.platform_bus);
}
