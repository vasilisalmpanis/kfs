const Bus = @import("../bus.zig").Bus;
const pci = @import("main.zig");
const drv = @import("../driver.zig");
const dev = @import("../device.zig");
const utils = @import("kernel").list;
const std = @import("std");
const arch = @import("arch");
const krn = @import("kernel");
const identifyDevice = @import("../pci-vendors.zig").identifyDevice;
const identifyClass = @import("../pci-vendors.zig").identifyClass;
const ConfigCommand = @import("./bus.zig").ConfigCommand;

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
    dev: dev.Device = undefined,

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

    pub fn register(self: *PCIDevice) void {
        pci.bus.pci_bus.add_dev(&self.dev) catch |err| {
            krn.logger.ERROR("Failer to add PCI device: {!}", .{err});
        };
    }

    pub fn clone(self: *const PCIDevice) ?*PCIDevice {
        if (krn.mm.kmalloc(PCIDevice)) |_dev| {
            _dev.* = self.*;
            return _dev;
        }
        return null;
    }

    pub fn read(self: *const PCIDevice, offset: u8) u32 {
        return readPCI(self.pci_cmd, offset);
    }

    pub fn write(self: *const PCIDevice, offset: u8, value: u32) void {
        writePCI(self.pci_cmd, offset, value);
    }
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

pub fn readPCIDev(cmd: ConfigCommand) ?PCIDevice {
    const vendor_id = readPCI16(cmd, PCI_VENDOR_ID);
    if (vendor_id == 0xFFFF) {
        return null;
    }
    var _dev = PCIDevice{};

    const reg0 = readPCI(cmd, 0x00);
    const reg1 = readPCI(cmd, 0x04);
    const reg2 = readPCI(cmd, 0x08);
    const reg3 = readPCI(cmd, 0x0C);

    _dev.vendor_id = @truncate(reg0);
    _dev.device_id = @truncate(reg0 >> 16);

    _dev.command = @truncate(reg1);
    _dev.status = @truncate(reg1 >> 16);

    _dev.revision_id = @truncate(reg2);
    _dev.prog_IF = @truncate(reg2 >> 8);
    _dev.subclass = @truncate(reg2 >> 16);
    _dev.class_code = @truncate(reg2 >> 24);

    _dev.cache_line_size = @truncate(reg3);
    _dev.latency_timer = @truncate(reg3 >> 8);
    _dev.header_type = @truncate(reg3 >> 16);
    _dev.bist = @truncate(reg3 >> 24);
    
    if ((_dev.header_type & 0x7F) == 0) {
        // General device
        _dev.bar0 = readPCI(cmd, PCI_BAR0);
        _dev.bar1 = readPCI(cmd, PCI_BAR1);
        _dev.bar2 = readPCI(cmd, PCI_BAR2);
        _dev.bar3 = readPCI(cmd, PCI_BAR3);
        _dev.bar4 = readPCI(cmd, PCI_BAR4);
        _dev.bar5 = readPCI(cmd, PCI_BAR5);

        _dev.cardbus_cis = readPCI(cmd, PCI_CARDBUS_CIS);

        const subsystem = readPCI(cmd, PCI_SUBSYSTEM_VENDOR_ID);
        _dev.subsystem_vendor_id = @truncate(subsystem);
        _dev.subsystem_id = @truncate(subsystem >> 16);

        _dev.expansion_rom_base_addr = readPCI(cmd, PCI_EXPANSION_ROM);

        _dev.capabil_ptr = readPCI8(cmd, PCI_CAPABILITIES);

        _dev.int_line = readPCI8(cmd, PCI_INTERRUPT_LINE);
        _dev.int_pin = readPCI8(cmd, PCI_INTERRUPT_PIN);
        _dev.min_grant = readPCI8(cmd, PCI_MIN_GRANT);
        _dev.max_latency = readPCI8(cmd, PCI_MAX_LATENCY);

        _dev.pci_cmd = cmd;
    }

    return _dev;
}
