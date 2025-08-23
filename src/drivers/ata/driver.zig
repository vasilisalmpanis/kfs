const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const utils = @import("kernel").list;
const std = @import("std");
const kernel = @import("kernel");
const ATADevice = @import("./device.zig").ATADevice;
const bus = @import("./bus.zig");

pub const ATADriver = struct {
    driver: drv.Driver,

    probe: *const fn(*ATADevice) anyerror!void,
    remove: *const fn(*ATADevice) anyerror!void,
};

// core probe wrapper
fn ata_probe_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const ata_dev: *ATADevice = @fieldParentPtr("dev", device);
    const ata_driver: *ATADriver = @fieldParentPtr("driver", driver);

    try ata_driver.probe(ata_dev);
}

fn ata_remove_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const ata_dev: *ATADevice = @fieldParentPtr("dev", device);
    const ata_driver: *ATADriver = @fieldParentPtr("driver", driver);

    try ata_driver.remove(ata_dev);
}

pub fn ata_register_driver(driver: *drv.Driver) !void {
    driver.probe = ata_probe_device;
    driver.remove = ata_remove_device;
    try driver.register(&bus.ata_bus);
}

pub fn ata_unregister_driver(driver: *drv.Driver) void {
    driver.unregister(&bus.ata_bus);
}
