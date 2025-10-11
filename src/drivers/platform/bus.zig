const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const std = @import("std");
const kernel = @import("kernel");

fn match(driver: *drv.Driver, device: *dev.Device) bool {
    return std.mem.startsWith(u8, device.name, driver.name);
}

pub var platform_bus: Bus = Bus{
    .name = "platform",
    .match = match,
    .scan = null,
    .drivers = null,
    .devices = null,
};

pub fn init() void {
    platform_bus.list.setup();
    platform_bus.register() catch |err| {
        kernel.logger.ERROR("Error while registering platform bus: {any}", .{err});
        return ;
    };
    kernel.logger.INFO("Platform bus is registered",.{});
}
