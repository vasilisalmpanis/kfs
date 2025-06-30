const std = @import("std");
const arch = @import("arch");
const krn = @import("kernel");
const identifyDevice = @import("./pci-vendors.zig").identifyDevice;
const identifyClass = @import("./pci-vendors.zig").identifyClass;

const CONFIG_ADDRESS               = 0xCF8;
const CONFIG_DATA                  = 0xCFC;

pub const PCI_VENDOR_ID            = 0x00;
pub const PCI_DEVICE_ID            = 0x02;
pub const PCI_COMMAND              = 0x04;
pub const PCI_STATUS               = 0x06;
pub const PCI_REVISION_ID          = 0x08;
pub const PCI_PROG_IF              = 0x09;
pub const PCI_SUBCLASS             = 0x0a;
pub const PCI_CLASS                = 0x0b;
pub const PCI_CACHE_LINE_SIZE      = 0x0c;
pub const PCI_LATENCY_TIMER        = 0x0d;
pub const PCI_HEADER_TYPE          = 0x0e;
pub const PCI_BIST                 = 0x0f;
pub const PCI_BAR0                 = 0x10;
pub const PCI_BAR1                 = 0x14;
pub const PCI_BAR2                 = 0x18;
pub const PCI_BAR3                 = 0x1C;
pub const PCI_BAR4                 = 0x20;
pub const PCI_BAR5                 = 0x24;
pub const PCI_CARDBUS_CIS          = 0x28;
pub const PCI_SUBSYSTEM_VENDOR_ID  = 0x2C;
pub const PCI_SUBSYSTEM_ID         = 0x2E;
pub const PCI_EXPANSION_ROM        = 0x30;
pub const PCI_CAPABILITIES         = 0x34;
pub const PCI_INTERRUPT_LINE       = 0x3C;
pub const PCI_INTERRUPT_PIN        = 0x3D;
pub const PCI_MIN_GRANT            = 0x3E;
pub const PCI_MAX_LATENCY          = 0x3F;


const PCI_SECONDARY_BUS            = 0x09;

const PCI_TYPE_BRIDGE              = 0x0604;
const PCI_TYPE_SATA                = 0x0106;
const PCI_NONE                     = 0xFFFF;


const HeaderType = enum(u8) {
    GENERAL_DEVICE = 0x0,
    PCI_TO_PCI_BRIDGE = 0x1,
    PCI_TO_CARDBUS_BRIDGE = 0x2,
};

pub const PCIDevice = struct {
    vendor_id: u16 = 0,
    device_id: u16 = 0,
    command: u16 = 0,
    status: u16 = 0,
    revision_id: u8 = 0,
    prog_IF: u8 = 0,
    subclass: u8 = 0,
    class_code: u8 = 0,
    cache_line_size: u8 = 0,
    latency_timer: u8 = 0,
    header_type: u8 = 0,
    bist: u8 = 0,
    bar0: u32 = 0,
    bar1: u32 = 0,
    bar2: u32 = 0,
    bar3: u32 = 0,
    bar4: u32 = 0,
    bar5: u32 = 0,
    cardbus_cis: u32 = 0,
    subsystem_vendor_id: u16 = 0,
    subsystem_id: u16 = 0,
    expansion_rom_base_addr: u32 = 0,
    capabil_ptr: u8 = 0,
    reserved_1: u8 = 0,
    reserved_2: u16 = 0,
    reserved_3: u32 = 0,
    int_line: u8 = 0,
    int_pin: u8 = 0,
    min_grant: u8 = 0,
    max_latency: u8 = 0,
    pci_cmd: ConfigCommand = ConfigCommand{},

    pub fn print(self: *const PCIDevice) void {
        krn.logger.INFO(
            \\============================
            \\  ||  Vendor id:      0x{X:0>4}
            \\  ||  Device id:      0x{X:0>4}
            \\  ||  Command:        0x{X:0>4}
            \\  ||  Status:         0x{X:0>4}
            \\  ||  Revision:       0x{X:0>2}
            \\  ||  Class:          0x{X:0>2}
            \\  ||  Subclass:       0x{X:0>2}
            \\  ||  Header type:    0x{X:0>2}
            \\  ||  BAR0:           0x{X:0>8}
            \\  ||  BAR1:           0x{X:0>8}
            \\  ||  BAR2:           0x{X:0>8}
            \\  ||  BAR3:           0x{X:0>8}
            \\  ||  BAR4:           0x{X:0>8}
            \\  ||  BAR5:           0x{X:0>8}
            \\  ||  class:          {s}
            \\  ||  name:           {s}
            , .{
                self.vendor_id,
                self.device_id,
                self.command,
                self.status,
                self.revision_id,
                self.class_code,
                self.subclass,
                self.header_type,
                self.bar0,
                self.bar1,
                self.bar2,
                self.bar3,
                self.bar4,
                self.bar5,
                identifyClass(
                    self.class_code,
                    self.subclass,
                ),
                identifyDevice(
                    self.vendor_id,
                    self.device_id,
                )
            }
        );
    }

    pub fn read(self: *const PCIDevice, offset: u8) u32 {
        return readPCI(self.pci_cmd, offset);
    }

    pub fn write(self: *const PCIDevice, offset: u8, value: u32) void {
        writePCI(self.pci_cmd, offset, value);
    }
};

const ConfigCommand = packed struct {
    always_zero: u2 = 0,
    reg_offset: u6 = 0,
    func_num: u3 = 0,
    dev_num: u5 = 0,
    bus_num: u8 = 0,
    reserved: u7 = 0,
    enable: bool = false,
};

fn writePCI(cmd: ConfigCommand, reg_offset: u8, value: u32) void {
    var _cmd = cmd;
    _cmd.always_zero = 0;
    _cmd.reserved = 0;
    _cmd.reg_offset = @truncate(reg_offset >> 2);
    _cmd.enable = true;
    arch.io.outl(CONFIG_ADDRESS, @as(u32, @bitCast(_cmd)));
    arch.io.outl(CONFIG_DATA, value);
}

fn readPCI(cmd: ConfigCommand, reg_offset: u8) u32 {
    var _cmd = cmd;
    _cmd.always_zero = 0;
    _cmd.reserved = 0;
    _cmd.reg_offset = @truncate(reg_offset >> 2);
    _cmd.enable = true;
    arch.io.outl(CONFIG_ADDRESS, @as(u32, @bitCast(_cmd)));
    return arch.io.inl(CONFIG_DATA);
}

fn readPCI16(cmd: ConfigCommand, reg_offset: u8) u16 {
    const data = readPCI(cmd, reg_offset & 0xFC);
    const shift = @as(u5, @intCast((reg_offset & 0x03) * 8));
    return @as(u16, @truncate(data >> shift));
}

fn readPCI8(cmd: ConfigCommand, reg_offset: u8) u8 {
    const data = readPCI(cmd, reg_offset & 0xFC);
    const shift = @as(u5, @intCast((reg_offset & 0x03) * 8));
    return @as(u8, @truncate(data >> shift));
}

fn readPCIDev(cmd: ConfigCommand) ?PCIDevice {
    const vendor_id = readPCI16(cmd, PCI_VENDOR_ID);
    if (vendor_id == 0xFFFF) {
        return null;
    }
    var dev = PCIDevice{};

    const reg0 = readPCI(cmd, 0x00);
    const reg1 = readPCI(cmd, 0x04);
    const reg2 = readPCI(cmd, 0x08);
    const reg3 = readPCI(cmd, 0x0C);

    dev.vendor_id = @truncate(reg0);
    dev.device_id = @truncate(reg0 >> 16);

    dev.command = @truncate(reg1);
    dev.status = @truncate(reg1 >> 16);

    dev.revision_id = @truncate(reg2);
    dev.prog_IF = @truncate(reg2 >> 8);
    dev.subclass = @truncate(reg2 >> 16);
    dev.class_code = @truncate(reg2 >> 24);

    dev.cache_line_size = @truncate(reg3);
    dev.latency_timer = @truncate(reg3 >> 8);
    dev.header_type = @truncate(reg3 >> 16);
    dev.bist = @truncate(reg3 >> 24);
    
    if ((dev.header_type & 0x7F) == 0) {
        // General device
        dev.bar0 = readPCI(cmd, PCI_BAR0);
        dev.bar1 = readPCI(cmd, PCI_BAR1);
        dev.bar2 = readPCI(cmd, PCI_BAR2);
        dev.bar3 = readPCI(cmd, PCI_BAR3);
        dev.bar4 = readPCI(cmd, PCI_BAR4);
        dev.bar5 = readPCI(cmd, PCI_BAR5);

        dev.cardbus_cis = readPCI(cmd, PCI_CARDBUS_CIS);

        const subsystem = readPCI(cmd, PCI_SUBSYSTEM_VENDOR_ID);
        dev.subsystem_vendor_id = @truncate(subsystem);
        dev.subsystem_id = @truncate(subsystem >> 16);

        dev.expansion_rom_base_addr = readPCI(cmd, PCI_EXPANSION_ROM);

        dev.capabil_ptr = readPCI8(cmd, PCI_CAPABILITIES);

        dev.int_line = readPCI8(cmd, PCI_INTERRUPT_LINE);
        dev.int_pin = readPCI8(cmd, PCI_INTERRUPT_PIN);
        dev.min_grant = readPCI8(cmd, PCI_MIN_GRANT);
        dev.max_latency = readPCI8(cmd, PCI_MAX_LATENCY);

        dev.pci_cmd = cmd;
    }

    return dev;
}

pub fn getDevice(class: u8, subclass: u8) ?PCIDevice {
    for (0..4) |bus_num| {
        for (0..32) |dev_num| {
            const cmd = ConfigCommand{
                .bus_num = @truncate(bus_num),
                .dev_num = @truncate(dev_num),
            };
            if (readPCIDev(cmd)) |device| {
                if ((device.header_type & 0x80) != 0) {
                    for (0..8) |func_num| {
                        var _cmd = cmd;
                        _cmd.func_num = @truncate(func_num);
                        if (readPCIDev(_cmd)) |dev| {
                            if (dev.class_code == class and dev.subclass == subclass) {
                                return dev;
                            }
                        }
                    }
                } else {
                    if (device.class_code == class and device.subclass == subclass) {
                        return device;
                    }
                }
            }
        }
    }
    return null;
}

pub const Iterator = struct {
    devices: *const std.ArrayList(PCIDevice),
    indices: []const usize,
    current: usize,
    
    pub fn next(self: *Iterator) ?*const PCIDevice {
        if (self.current >= self.indices.len) return null;
        const device = &self.devices.items[self.indices[self.current]];
        self.current += 1;
        return device;
    }
};

pub const PCIManager = struct {
    devices: std.ArrayList(PCIDevice) = undefined,
    class_index: std.AutoHashMap(u16, std.ArrayList(usize)) = undefined,

    pub fn init() PCIManager {
        var manager = PCIManager{};
        manager.devices = std.ArrayList(PCIDevice).init(
            krn.mm.kernel_allocator.allocator()
        );
        manager.class_index = std.AutoHashMap(u16, std.ArrayList(usize)).init(
            krn.mm.kernel_allocator.allocator()
        );
        return manager;
    }

    pub fn addDevice(self: *PCIManager, device: PCIDevice) !void {
        const idx = self.devices.items.len;
        try self.devices.append(device);
        const key: u16 = (@as(u16, @intCast(device.class_code)) << 8) | device.subclass;
        var class_list = self.class_index.get(key)
            orelse std.ArrayList(usize).init(self.devices.allocator);
        try class_list.append(idx);
        try self.class_index.put(key, class_list);

    }

    pub fn findByClass(
        self: *const PCIManager,
        class_code: u8,
        subclass: u8
    ) ?[]const usize {
        const key: u16 = (@as(u16, @intCast(class_code)) << 8) | subclass;
        if (self.class_index.get(key)) |indices| {
            return indices.items;
        }
        return null;
    }

    pub fn iterateByClass(
        self: *const PCIManager,
        class_code: u8,
        subclass: u8
    ) Iterator {
        const indices = self.findByClass(
            class_code,
            subclass
        ) orelse &[_]usize{};
        return Iterator{
            .devices = &self.devices,
            .indices = indices,
            .current = 0,
        };
    }

    pub fn iterate(self: *const PCIManager) Iterator {
        return Iterator{
            .devices = &self.devices,
            .indices = self.devices.items,
            .current = 0,
        };
    }

    pub fn scanDevices(self: *PCIManager) void {
        for (0..4) |bus_num| {
            for (0..32) |dev_num| {
                const cmd = ConfigCommand{
                    .bus_num = @truncate(bus_num),
                    .dev_num = @truncate(dev_num),
                };
                if (readPCIDev(cmd)) |device| {
                    if ((device.header_type & 0x80) != 0) {
                        for (0..8) |func_num| {
                            var _cmd = cmd;
                            _cmd.func_num = @truncate(func_num);
                            if (readPCIDev(_cmd)) |dev| {
                                krn.logger.INFO("DEVICE {d} ON BUS {d} FUNC {d}", .{
                                    dev_num, bus_num, func_num
                                });
                                self.addDevice(dev) catch {
                                    krn.logger.ERROR("Failer to add PCI device", .{});
                                };
                                dev.print();
                            }
                        }
                    } else {
                        krn.logger.INFO("DEVICE {d} ON BUS {d}", .{
                            dev_num, bus_num
                        });
                        self.addDevice(device) catch {
                            krn.logger.ERROR("Failer to add PCI device", .{});
                        };
                        device.print();
                    }
                }
            }
        }
    }
};

pub var pci_manager: PCIManager = undefined;

pub export fn init() linksection(".init.text") void {
    pci_manager = PCIManager.init();
    pci_manager.scanDevices();
}

export var exported_data: *const fn() callconv(.c) void linksection(".init_call.early") = init;
