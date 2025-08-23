const Bus = @import("../bus.zig").Bus;
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const std = @import("std");
const arch = @import("arch");
const krn = @import("kernel");
const utils = krn.list;

const pci = @import("./main.zig");

fn match(driver: *drv.Driver, device: *dev.Device) bool {
    const pci_driver: *pci.PCIDriver = @fieldParentPtr("driver", driver);
    const pci_device: *pci.PCIDevice = @fieldParentPtr("dev", device);
    if (pci_driver.ids) |ids| {
        for (ids) |id| {
            if (id.match(pci_device))
                return true;
        }

    }
    return std.mem.eql(u8, driver.name, device.name);
}

pub const ConfigCommand = packed struct {
    always_zero: u2 = 0,
    reg_offset: u6 = 0,
    func_num: u3 = 0,
    dev_num: u5 = 0,
    bus_num: u8 = 0,
    reserved: u7 = 0,
    enable: bool = false,
};

fn scan(bus: *Bus) void {
    for (0..4) |bus_num| {
        for (0..32) |dev_num| {
            const cmd = ConfigCommand{
                .bus_num = @truncate(bus_num),
                .dev_num = @truncate(dev_num),
            };
            if (pci.device.readPCIDev(cmd)) |device| {
                if ((device.header_type & 0x80) != 0) {
                    for (0..8) |func_num| {
                        var _cmd = cmd;
                        _cmd.func_num = @truncate(func_num);
                        if (pci.device.readPCIDev(_cmd)) |_dev| {
                            // krn.logger.INFO("DEVICE {d} ON BUS {d} FUNC {d}", .{
                            //     dev_num, bus_num, func_num
                            // });
                            if (_dev.clone()) |_d| {
                                var new_dev = _d;
                                if (krn.mm.kmallocSlice(u8, 12)) |name| {
                                    _ = std.fmt.bufPrint(
                                        name,
                                        "0000:{x:0>2}:{x:0>2}:{x}",
                                        .{
                                            @as(u16, @truncate(bus_num)),
                                            @as(u16, @truncate(dev_num)),
                                            @as(u8, @truncate(func_num)),
                                        }
                                    ) catch null;
                                    new_dev.dev.setup(name, bus);
                                    new_dev.register();
                                }
                            }
                            // _dev.print();
                        }
                    }
                } else {
                    // krn.logger.INFO("DEVICE {d} ON BUS {d}", .{
                    //     dev_num, bus_num
                    // });
                    if (device.clone()) |_d| {
                        var new_dev = _d;
                        if (krn.mm.kmallocSlice(u8, 12)) |name| {
                            _ = std.fmt.bufPrint(
                                name,
                                "0000:{x:0>2}:{x:0>2}:{x}",
                                .{
                                    @as(u18, @truncate(bus_num)),
                                    @as(u18, @truncate(dev_num)),
                                    0,
                                }
                            ) catch null;
                            new_dev.dev.setup(name, bus);
                            new_dev.register();
                        }
                    }
                    // device.print();
                }
            }
        }
    }
}

pub var pci_bus: Bus = Bus{
    .name = "pci",
    .match = match,
    .scan = scan,
    .drivers = null,
    .devices = null,
};

pub fn init() void {
    pci_bus.list.setup();
    pci_bus.register() catch |err| {
        krn.logger.ERROR("Error while registering pci bus: {!}", .{err});
        return ;
    };
    krn.logger.INFO("PCI bus is registered",.{});
}
