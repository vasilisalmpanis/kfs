const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");

fn probe(driver: *drv.Driver, device: *dev.Device) !void{
    _ = driver;
    _ = device;
}

fn match(driver: *drv.Driver, device: *dev.Device) bool {
    _ = driver;
    _ = device;
}

fn remove(driver: *drv.Driver, device: *dev.Device) !void {
    _ = driver;
    _ = device;
}

var platform_bus: Bus = Bus{
    .probe = probe,
    .match = match,
    .remove = remove, 
    .drivers = null,
    .devices = null,
};
