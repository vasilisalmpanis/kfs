const drv = @import("../main.zig");
const pci = drv.pci;
const kernel = @import("kernel");

var ata_driver = pci.PCIDriver{
    .driver = drv.driver.Driver{
        .fops = null,
        .list = undefined,
        .name = "ata",
        .probe = undefined,
        .remove = undefined,
    },
    .ids = ids,
    .probe = ata_probe,
    .remove = ata_remove,
};

const ids: [] const pci.driver.PCIid = &[_]pci.driver.PCIid{
    pci.driver.PCIid{
       .class = 0x1, 
       .subclass = 0x1,
       .deviceid = 0x7010,
       .vendorid = 0x8086,
    },
};

fn ata_probe(device: *pci.PCIDevice) !void {
    kernel.logger.WARN("ATA DEVICE {s}\n", .{device.dev.name});
}

fn ata_remove(_: *pci.PCIDevice) !void {
}

pub fn init() void {
    pci.driver.pci_register_driver(&ata_driver.driver) catch {
        kernel.logger.ERROR("ATA driver cannot be registered\n", .{});
    };
}
