const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const utils = @import("kernel").list;
const std = @import("std");
const kernel = @import("kernel");

pub const PlatformDevice = struct {
    dev: dev.Device,

    pub fn alloc(name: []const u8) ?*PlatformDevice {
        if (kernel.mm.kmalloc(PlatformDevice)) |new_dev| {
            if (kernel.mm.kmallocSlice(u8, name.len)) |dev_name| {
                @memcpy(dev_name[0..], name[0..]);
                new_dev.dev.setup(dev_name, &platform_bus);
                return new_dev;
            }
        }
        return null;
    }

    pub fn free(self: *PlatformDevice) void {
        kernel.mm.kfree(self.dev.name.ptr);
        kernel.mm.kfree(self);
    }

    pub fn register(self: *PlatformDevice) !void {
        self.dev.bus = &platform_bus;
        self.dev.bus.add_dev(&self.dev) catch {};
    }

    pub fn unregister(self: *PlatformDevice) !void {
        _ = self;
        // TODO:
    }
};

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

fn match(driver: *drv.Driver, device: *dev.Device) bool {
    kernel.logger.INFO("matching", .{});
    return std.mem.eql(u8, driver.name, device.name);
}

var platform_bus: Bus = Bus{
    .name = "platform",
    .match = match,
    .drivers = null,
    .devices = null,
};

pub fn init_platform() void {
    platform_bus.register();
    kernel.logger.INFO("Platform bus is registered",.{});
}

pub fn platform_register_driver(driver: *drv.Driver) void {
    driver.probe = platform_probe_device;
    driver.remove = platform_remove_device;
    driver.register(&platform_bus);
}

pub fn platform_unregister_driver(driver: *drv.Driver) void {
    driver.unregister(&platform_bus);
}
