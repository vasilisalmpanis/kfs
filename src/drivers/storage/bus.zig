const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const std = @import("std");
const kernel = @import("kernel");

fn match(_: *drv.Driver, _: *dev.Device) bool {
    return true;
}

pub var storage_bus: Bus = Bus{
    .name = "storage",
    .match = match,
    .scan = null,
    .drivers = null,
    .devices = null,
};

pub fn init() void {
    storage_bus.list.setup();
    storage_bus.register() catch |err| {
        kernel.logger.ERROR("Error while registering platform bus: {!}", .{err});
        return ;
    };
    kernel.logger.INFO("Platform bus is registered",.{});
}
