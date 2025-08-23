const drv = @import("../driver.zig");
const PCIDevice = @import("device.zig").PCIDevice;
const dev = @import("../device.zig");
const bus = @import("bus.zig");

pub const PCIDriver = struct {
    driver: drv.Driver,
    ids: ?[] const PCIid,

    probe: *const fn(*PCIDevice) anyerror!void,
    remove: *const fn(*PCIDevice) anyerror!void,
};

pub const PCIid = struct {
    class: u8,
    subclass: u8,
    vendorid: u16,
    deviceid: u16,

    pub fn match(self: * const PCIid, device: *const PCIDevice) bool {
        if (self.class != device.class_code or
            self.subclass != device.subclass)
            return false;
        if (self.vendorid == 0 and
            self.deviceid == 0)
            return true;
        if (self.vendorid != device.vendor_id
            or self.deviceid != device.device_id)
            return false;
        return true;
    }
};

// core probe wrapper
fn pci_probe_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const pci_dev: *PCIDevice = @fieldParentPtr("dev", device);
    const pci_driver: *PCIDriver = @fieldParentPtr("driver", driver);

    try pci_driver.probe(pci_dev);
}

fn pci_remove_device(driver: *drv.Driver, device: *dev.Device) anyerror!void {
    const pci_dev: *PCIDevice = @fieldParentPtr("dev", device);
    const pci_driver: *PCIDriver = @fieldParentPtr("driver", driver);

    try pci_driver.remove(pci_dev);
}

pub fn pci_register_driver(driver: *drv.Driver) !void {
    driver.probe = pci_probe_device;
    driver.remove = pci_remove_device;
    try driver.register(&bus.pci_bus);
}

pub fn pci_unregister_driver(driver: *drv.Driver) void {
    driver.unregister(&bus.pci_bus);
}
