const drv = @import("../main.zig");
const pci = drv.pci;
const kernel = @import("kernel");
const drive = @import("../storage/ata.zig");

var ide_driver = pci.PCIDriver{
    .driver = drv.driver.Driver{
        .fops = null,
        .list = undefined,
        .name = "IDE",
        .probe = undefined,
        .remove = undefined,
    },
    .ids = ids,
    .probe = ide_probe,
    .remove = ide_remove,
};

const ids: [] const pci.driver.PCIid = &[_]pci.driver.PCIid{
    pci.driver.PCIid{
       .class = 0x1, 
       .subclass = 0x1,
       .deviceid = 0,
       .vendorid = 0,
    },
};

fn ide_probe(device: *pci.PCIDevice) !void {
    drive.ata_init(device);
}

fn ide_remove(_: *pci.PCIDevice) !void {
}

pub fn init() void {
    pci.driver.pci_register_driver(&ide_driver.driver) catch {
        kernel.logger.ERROR("IDE driver cannot be registered\n", .{});
    };
}
