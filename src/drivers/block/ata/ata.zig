// Keep current drive saved 
// Only select another if we need to use another
// The suggestion is to read the Status register FIFTEEN TIMES, and only pay attention to the value returned by the last one -- after selecting a new master or slave device
const std = @import("std");
const dbg = @import("debug");
const kernel = @import("kernel");
const irq = kernel.irq;
const arch = @import("arch");
const lst = kernel.list;
const pci = @import("../../pci.zig");

// BUS MASTER IDE
const BMIDE_COMMAND             = 0x00;
const BMIDE_STATUS              = 0x02;
const BMIDE_PRDT_ADDR           = 0x04;

const BMIDE_CMD_START           = 0x01;
const BMIDE_CMD_READ            = 0x08;

const BMIDE_STATUS_ACTIVE       = 0x01;
const BMIDE_STATUS_ERROR        = 0x02;
const BMIDE_STATUS_INTERRUPT    = 0x04;
const BMIDE_STATUS_DMA0_CAPABLE = 0x20;
const BMIDE_STATUS_DMA1_CAPABLE = 0x40;
const BMIDE_STATUS_SIMPLEX      = 0x80;

// 
const ATA_PRIMARY_IRQ       = 14;
const ATA_SECONDARY_IRQ     = 15;
const ATA_PRIMARY_IO        = 0x1F0;
const ATA_SECONDARY_IO      =  0x170;
const ATA_PRIMARY_STATUS    = 0x3F6;
const ATA_SECONDARY_STATUS  = 0x376;

const ATA_SR_BSY   = 0x80;
const ATA_SR_DRDY  = 0x40;
const ATA_SR_DF    = 0x20;
const ATA_SR_DSC   = 0x10;
const ATA_SR_DRQ   = 0x08;
const ATA_SR_CORR  = 0x04;
const ATA_SR_IDX   = 0x02;
const ATA_SR_ERR   = 0x01;

const ATA_ER_BBK   = 0x80;
const ATA_ER_UNC   = 0x40;
const ATA_ER_MC    = 0x20;
const ATA_ER_IDNF  = 0x10;
const ATA_ER_MCR   = 0x08;
const ATA_ER_ABRT  = 0x04;
const ATA_ER_TK0NF = 0x02;
const ATA_ER_AMNF  = 0x01;

const ATA_CMD_READ_PIO         = 0x20;
const ATA_CMD_READ_PIO_EXT     = 0x24;
const ATA_CMD_READ_DMA         = 0xC8;
const ATA_CMD_READ_DMA_EXT     = 0x25;
const ATA_CMD_WRITE_PIO        = 0x30;
const ATA_CMD_WRITE_PIO_EXT    = 0x34;
const ATA_CMD_WRITE_DMA        = 0xCA;
const ATA_CMD_WRITE_DMA_EXT    = 0x35;
const ATA_CMD_CACHE_FLUSH      = 0xE7;
const ATA_CMD_CACHE_FLUSH_EXT  = 0xEA;
const ATA_CMD_PACKET           = 0xA0;
const ATA_CMD_IDENTIFY_PACKET  = 0xA1;
const ATA_CMD_IDENTIFY         = 0xEC;

const ATAPI_CMD_READ   = 0xA8;
const ATAPI_CMD_EJECT  = 0x1B;

const ATA_IDENT_DEVICETYPE   =  0;
const ATA_IDENT_CYLINDERS    =  2;
const ATA_IDENT_HEADS        =  6;
const ATA_IDENT_SECTORS      =  12;
const ATA_IDENT_SERIAL       =  20;
const ATA_IDENT_MODEL        =  54;
const ATA_IDENT_CAPABILITIES =  98;
const ATA_IDENT_FIELDVALID   =  106;
const ATA_IDENT_MAX_LBA      =  120;
const ATA_IDENT_COMMANDSETS  =  164;
const ATA_IDENT_MAX_LBA_EXT  =  200;

const IDE_ATA    = 0x00;
const IDE_ATAPI  = 0x01;
 
const ATA_MASTER = 0x00;
const ATA_SLAVE  = 0x01;

// IO Port Inputs
const ATA_REG_DATA        = 0x00;
const ATA_REG_FEATURES    = 0x01;
const ATA_REG_SECCOUNT0   = 0x02;
const ATA_REG_LBA0        = 0x03;
const ATA_REG_LBA1        = 0x04;
const ATA_REG_LBA2        = 0x05;
const ATA_REG_HDDEVSEL    = 0x06;
const ATA_REG_COMMAND     = 0x07;

// IO Port Outputs
const ATA_REG_ERROR       = 0x01;
const ATA_REG_STATUS      = 0x07;

const ATA_REG_SECCOUNT1   = 0x08;
const ATA_REG_LBA3        = 0x09;
const ATA_REG_LBA4        = 0x0A;
const ATA_REG_LBA5        = 0x0B;
const ATA_REG_CONTROL     = 0x0C;
const ATA_REG_ALTSTATUS   = 0x0C;
const ATA_REG_DEVADDRESS  = 0x0D;

// Channels:
const ATA_PRIMARY   = 0x00;
const ATA_SECONDARY = 0x01;
 
// Directions:
const ATA_READ  = 0x00;
const ATA_WRITE = 0x013;

const ATA_Operation = enum(u8) {
    ATA_OP_NONE = 0,
    ATA_OP_READ,
    ATA_OP_WRITE,
    ATA_OP_IDENTIFY
};

const ATA_Status = enum(u8) {
    ATA_STATUS_IDLE = 0,
    ATA_STATUS_BUSY,
    ATA_STATUS_COMPLETE,
    ATA_STATUS_ERROR,
    ATA_STATUS_TIMEOUT
};

const PRDEntry = struct {
    phys: u32,
    size: u16,
    reserved: u8,
    eot: u8,
};

const ChannelType = enum {
    PRIMARY_MASTER,
    PRIMARY_SLAVE,
    SECONDARY_MASTER,
    SECONDARY_SLAVE,

    pub fn isMaster(self: ChannelType) bool {
        return self == .PRIMARY_MASTER or self == .SECONDARY_MASTER;
    }

    pub fn isPrimary(self: ChannelType) bool {
        return self == .PRIMARY_MASTER or self == .PRIMARY_SLAVE;
    }

    pub fn getBus(self: ChannelType) u8 {
        return if (self.isPrimary()) ATA_PRIMARY else ATA_SECONDARY;
    }

    pub fn getChannel(self: ChannelType) u8 {
        return if (self.isMaster()) ATA_MASTER else ATA_SLAVE;
    }

    pub fn getIOReg(self: ChannelType) u16 {
        return if (self.isPrimary()) ATA_PRIMARY_IO else ATA_SECONDARY_IO;
    }

    pub fn getStatusReg(self: ChannelType) u16 {
        return if (self.isPrimary()) ATA_PRIMARY_STATUS else ATA_SECONDARY_STATUS;
    }

    pub fn getIRQ(self: ChannelType) u32 {
        return if (self.isPrimary()) ATA_PRIMARY_IRQ else ATA_SECONDARY_IRQ;
    }

    pub fn getBMIDEOffset(self: ChannelType) u8 {
        return if (self.isPrimary()) 0 else 0x08;
    }

    pub fn getDevCmd(self: ChannelType) u8 {
        return if (self.isPrimary()) 0xE0 else 0xF0;
    }
};

var current_channel: ChannelType = .PRIMARY_MASTER;

const ATADrive = struct {
    name: [41]u8 = .{0} ** 41,
    channel: ChannelType = .PRIMARY_MASTER,

    io_base: u16 = 0,
    ctrl_base: u16 = 0,
    bmide_base: u16 = 0,

    irq_num: u32 = 0,

    current_op: ATA_Operation   = .ATA_OP_NONE,
    status:     ATA_Status      = .ATA_STATUS_IDLE,
    device_cmd: u8 = 0,

    buffer: []u8 = undefined,

    lba28: u32 = 0,
    lba48: u64 = 0,
    drive: u8 = 0,

    irq_enabled: bool = false,

    // DMA
    prdt_phys: u32 = 0,
    prdt_virt: u32 = 0,
    dma_buff_phys: u32 = 0,
    dma_buff_virt: u32 = 0,
    dma_initialized: bool = false,

    const SECTOR_SIZE = 512;
    const DMA_BUFFER_PAGES = 8;
    const TIMEOUT_READY = 10000;
    const TIMEOUT_DMA = 1000000;
    const STATUS_READ_COUNT = 15;

    fn init(
        ch_type: ChannelType,
        bmide_base: u16,
        name: [41]u8
    ) ?ATADrive {
        var drv = ATADrive{
            .channel = ch_type,
            .io_base = ch_type.getIOReg(),
            .ctrl_base = ch_type.getStatusReg(),
            .bmide_base = bmide_base + ch_type.getBMIDEOffset(),
            .irq_num = ch_type.getIRQ(),
            .device_cmd = ch_type.getDevCmd(),
        };
        if (kernel.mm.kmallocArray(u8, SECTOR_SIZE)) |array| {
            drv.buffer = array[0..SECTOR_SIZE];
        } else {
            return null;
        }
        @memcpy(drv.name[0..41], name[0..41]);
        drv.lba28 = @as(*u32, @ptrCast(@alignCast(&ide_buf[60]))).*;
        drv.lba48 = @as(*u64, @ptrCast(@alignCast(&ide_buf[100]))).*;

        drv.initDMA();
        return drv;
    }

    fn selectChannel(self: *const ATADrive) void {
        if (self.channel != current_channel) {
            ideSelectChannel(self.channel);
        }
    }

    fn initDMA(self: *ATADrive) void {
        const phys = kernel.mm.virt_memory_manager.pmm.allocPages(DMA_BUFFER_PAGES + 1);
        const buff_phys = phys + kernel.mm.PAGE_SIZE;

        kernel.logger.INFO("DMA PHYS: 0x{X:0>8} - 0x{X:0>8}", .{
            phys, phys + (DMA_BUFFER_PAGES + 1) * kernel.mm.PAGE_SIZE
        });

        const virt = kernel.mm.virt_memory_manager.findFreeSpace(
            DMA_BUFFER_PAGES + 1,
            0xD0000000,
            0xE0000000,
            false
        );
        kernel.mm.virt_memory_manager.mapPage(virt, phys, .{});
        @memset(@as([*]u8, @ptrFromInt(virt))[0..4096], 0);

        const buff_virt = virt + kernel.mm.PAGE_SIZE;

        for (0..DMA_BUFFER_PAGES) |i| {
            const vrt = buff_virt + i * kernel.mm.PAGE_SIZE;
            const phs = buff_phys + i * kernel.mm.PAGE_SIZE;
            kernel.mm.virt_memory_manager.mapPage(
                vrt,
                phs,
                .{}
            );
            @memset(@as([*]u8, @ptrFromInt(vrt))[0..4096], 0);
        }

        self.prdt_phys = phys;
        self.prdt_virt = virt;
        self.dma_buff_phys = buff_phys;
        self.dma_buff_virt = buff_virt;

        const prdt: *PRDEntry = @ptrFromInt(virt);
        prdt.phys = buff_phys;
        prdt.size = 8 * kernel.mm.PAGE_SIZE;
        prdt.reserved = 0;
        prdt.eot = 0x80;

        const status = arch.io.inb(self.bmide_base + BMIDE_STATUS);
        arch.io.outb(self.bmide_base + BMIDE_STATUS, status | 0x06);
        arch.io.outb(self.bmide_base + BMIDE_COMMAND, 0x00);

        arch.io.outl(self.bmide_base + BMIDE_PRDT_ADDR, phys);
        self.dma_initialized = true;
    }

    fn delay(self: *const ATADrive) void {
        for (0..4) |_| {
            _ = self.ata_read_reg(ATA_REG_ALTSTATUS);
        }
    }

    fn poll_ide(self: *const ATADrive) void {
        self.delay();
        while (self.ata_read_reg(ATA_REG_STATUS) & ATA_SR_BSY != 0) {}
        var status: u8 = 0;
        while (status & ATA_SR_DRQ == 0) {
            status = self.ata_read_reg(ATA_REG_STATUS);
            if (status & ATA_SR_ERR != 0) {
                kernel.logger.INFO("error in polling", .{});
                return;
            }
        }
    }

    fn read_sectors(self: *const ATADrive, lba: u32, num_sectors: u8) []const u8 {
        const device_cmd: u8 = self.device_cmd | @as(u8, @truncate((lba >> 24) & 0x0F));
        self.ata_write_reg(ATA_REG_SECCOUNT0, num_sectors);
        self.ata_write_reg(ATA_REG_LBA0, @truncate(lba));
        self.ata_write_reg(ATA_REG_LBA1, @truncate(lba >> 8));
        self.ata_write_reg(ATA_REG_LBA2, @truncate(lba >> 16));
        self.ata_write_reg(ATA_REG_HDDEVSEL, device_cmd);
        self.ata_write_reg(ATA_REG_COMMAND, ATA_CMD_READ_PIO);
        self.poll_ide();
        const sectors: u32 = if (num_sectors == 0) 256 else num_sectors;
        for (0..256 * sectors) |i| {
            const word = arch.io.inw(self.io_base + ATA_REG_DATA);
            self.buffer[i*2]     = @truncate(word);
            self.buffer[i*2 + 1] = @truncate(word >> 8);
        }
        self.delay();
        return self.buffer[0..512 * sectors];
    }

    fn waitNotBusy(self: *const ATADrive) bool {
        var timeout: u32 = TIMEOUT_READY;
        while (timeout > 0) {
            const status = self.ata_read_reg(ATA_REG_STATUS);
            if (status & ATA_SR_BSY == 0) {
                return true;
            }
            timeout -= 1;
        }
        return false;
    }

    fn waitReady(self: *const ATADrive) bool {
        var timeout: u32 = TIMEOUT_READY;
        while (timeout > 0) {
            const status = self.ata_read_reg(ATA_REG_STATUS);
            if (status & ATA_SR_BSY == 0 and status & ATA_SR_DRDY != 0) {
                return true;
            }
            timeout -= 1;
        }
        return false;
    }

    fn waitDataReady(self: *const ATADrive) bool {
        if (!self.waitNotBusy()) return false;
        var timeout: u32 = TIMEOUT_READY;
        while (timeout > 0) {
            const status = self.ataReadReg(ATA_REG_STATUS);
            if (status & ATA_SR_ERR != 0) {
                const err = self.ataReadReg(ATA_REG_ERROR);
                kernel.logger.ERROR("ATA Error: status=0x{X}, error=0x{X}", .{status, err});
                return false;
            }
            if (status & ATA_SR_DRQ != 0) return true;
            timeout -= 1;
        }
    }

    fn readSectorsDMA(self: *const ATADrive, lba: u32, num_sectors: u8) void {
        if (!self.dma_initialized or !self.waitReady()) {
            kernel.logger.ERROR("Drive not ready", .{});
            return;
        }

        const prdt: *PRDEntry = @ptrFromInt(self.prdt_virt);
        const transfer_size = @as(u16, if (num_sectors == 0) 256 else num_sectors) * 512;
        prdt.size = transfer_size;

        const status = arch.io.inb(self.bmide_base + BMIDE_STATUS);
        arch.io.outb(self.bmide_base + BMIDE_STATUS, status | 0x06);
        arch.io.outb(self.bmide_base + BMIDE_COMMAND, BMIDE_CMD_READ);

        const device_cmd: u8 = self.device_cmd | @as(u8, @truncate((lba >> 24) & 0x0F));
        self.ata_write_reg(ATA_REG_SECCOUNT0, num_sectors);
        self.ata_write_reg(ATA_REG_LBA0, @truncate(lba));
        self.ata_write_reg(ATA_REG_LBA1, @truncate(lba >> 8));
        self.ata_write_reg(ATA_REG_LBA2, @truncate(lba >> 16));
        self.ata_write_reg(ATA_REG_HDDEVSEL, device_cmd);

        arch.io.outb(self.bmide_base + BMIDE_COMMAND, BMIDE_CMD_READ | BMIDE_CMD_START);
        self.ata_write_reg(ATA_REG_COMMAND, ATA_CMD_READ_DMA);
        
        self.delay();
        self.waitDMA();
        return;
    }

    fn waitDMA(self: *const ATADrive) void {
        var timeout: u32 = TIMEOUT_DMA;
        
        while (timeout > 0) {
            const bmide_status = arch.io.inb(self.bmide_base + BMIDE_STATUS);
            const ata_status = self.ata_read_reg(ATA_REG_STATUS);
            
            if (bmide_status & BMIDE_STATUS_ERROR != 0 or ata_status & ATA_SR_ERR != 0) {
                kernel.logger.ERROR("DMA transfer error. BMIDE: 0x{X}, ATA: 0x{X}", .{bmide_status, ata_status});
                self.stopDMA();
                return;
            }
            
            if (bmide_status & BMIDE_STATUS_INTERRUPT != 0 and ata_status & ATA_SR_BSY == 0) {
                // kernel.logger.INFO("Read DMA finished successfully|", .{});
                self.stopDMA();                
                arch.io.outb(self.bmide_base + BMIDE_STATUS, bmide_status | BMIDE_STATUS_INTERRUPT);
                self.delay();
                const sector: []const u8 = @as([*]u8, @ptrFromInt(self.dma_buff_virt))[0..512];
                if (!std.mem.allEqual(u8, sector, 0)) {
                    kernel.logger.INFO("DATA: {s}", .{sector});
                }
                return ;
            }
            timeout -= 1;
        }
        
        kernel.logger.ERROR("DMA transfer timeout", .{});
        self.stopDMA();
        return;
    }

    fn stopDMA(self: *const ATADrive) void {
        arch.io.outb(self.bmide_base + BMIDE_COMMAND, 0x00);
    }

    inline fn ata_write_reg(channel: *const ATADrive, reg: u8, value: u8) void {
        arch.io.outb(channel.io_base + reg, value);
    }

    inline fn ata_read_reg(channel: *const ATADrive, reg: u8) u8 {
        return arch.io.inb(channel.io_base + reg);
    }

    pub fn read_full_drive(self: *const ATADrive) void {
        self.selectChannel();
        const num_sec: u32 = 1;
        for (0..self.lba28 / num_sec) |i| {
            const lba = i * num_sec;
            const sector = self.read_sectors(lba, num_sec);
            if (!std.mem.allEqual(u8, sector, 0)) {
                kernel.logger.INFO("{d}: {s}", .{ lba, sector });
            }
        }
    }

    pub fn read_full_drive_dma(self: *const ATADrive) void {
        self.selectChannel();
        const num_sec: u32 = 1;
        for (0..self.lba28 / num_sec) |i| {
            const lba = i * num_sec;
            self.readSectorsDMA(lba, 1);
        }
    }
};

var ide_buf: [*]u16 = undefined;

pub fn ata_primary() void {
    // kernel.logger.DEBUG("primary\n", .{});
}

pub fn ata_secondary() void {
    kernel.logger.DEBUG("secondary\n", .{});
}

fn ideSelectChannel(ch_type: ChannelType) void {
    const io_base: u16 = ch_type.getIOReg();
    const cmd: u8 = if (ch_type.isMaster()) 0xA0 else 0xB0;
    current_channel = ch_type;
    arch.io.outb(io_base + ATA_REG_HDDEVSEL, cmd);
}

fn ata_identify(ch_type: ChannelType) u8 {
    const io_base: u16 = ch_type.getIOReg();
    ideSelectChannel(ch_type);
    // Check if any drive present and ready
    var status = arch.io.inb(io_base + ATA_REG_STATUS);
    if (status == 0 or status == 0xFF) {
        return 0;
    }
    // ATA specs say these values must be zero before sending IDENTIFY */
    arch.io.outb(io_base + ATA_REG_SECCOUNT0, 0);
    arch.io.outb(io_base + ATA_REG_LBA0, 0);
    arch.io.outb(io_base + ATA_REG_LBA1, 0);
    arch.io.outb(io_base + ATA_REG_LBA2, 0);
    // Now, send IDENTIFY */
    arch.io.outb(io_base + ATA_REG_COMMAND, ATA_CMD_IDENTIFY);
    // Now, poll untill BSY is clear. */
    while(arch.io.inb(io_base + ATA_REG_STATUS) & ATA_SR_BSY != 0) {}
    status = arch.io.inb(io_base + ATA_REG_STATUS);
    while(!(status & ATA_SR_DRQ != 0)) {
        if(status & ATA_SR_ERR != 0)
        {
            kernel.logger.ERROR("{s} status 0x{x}\n", .{@tagName(ch_type), status});
            return 0;
        }
        status = arch.io.inb(io_base + ATA_REG_STATUS);
    }
    for(0..256) |i| {
        ide_buf[i] = arch.io.inw(io_base + ATA_REG_DATA);
    }
    irq.registerHandler(
        ch_type.getIRQ(),
        if (ch_type.isPrimary()) ata_primary else ata_secondary
    );
    return 1;
}

fn ata_probe_channel(
    ch_type: ChannelType,
    ide_device: *const pci.PCIDevice
) ?ATADrive {
    var str: [41]u8 = .{0} ** 41;
    if(ata_identify(ch_type) != 0)
    {
        for (0..20) |i| {
            const word_idx = ATA_IDENT_MODEL / 2 + i;
            const word = ide_buf[word_idx];

            str[i * 2] = @truncate(word >> 8);
            str[i * 2 + 1] = @truncate(word & 0xFF);
        }

        var pci_cmd = ide_device.read(pci.PCI_COMMAND);
        if (pci_cmd & (1 << 2) == 0) {
            // Enable bus master
            pci_cmd |= (1 << 2);
            ide_device.write(pci.PCI_COMMAND, pci_cmd);
        }

        if (ATADrive.init(
            ch_type,
            @truncate(ide_device.bar4 & 0xFFF0),
            str
        )) |drv| {
            kernel.logger.INFO("ATA DRIVE {s}\n{any}\n", .{drv.name, drv});
            return drv;
        }
    }
    return null;
}

pub const Iterator = struct {
    drives: *const std.ArrayList(ATADrive),
    current: usize,
    
    pub fn next(self: *Iterator) ?*const ATADrive {
        if (self.current >= self.drives.items.len) return null;
        const drive = &self.drives.items[self.current];
        self.current += 1;
        return drive;
    }
};

pub const ATAManager = struct {
    drives: std.ArrayList(ATADrive) = undefined,

    pub fn init() ATAManager {
        var manager = ATAManager{};
        manager.drives = std.ArrayList(ATADrive).init(
            kernel.mm.kernel_allocator.allocator(),
        );
        return manager;
    }

    pub fn addDevice(self: *ATAManager, device: ATADrive) !void {
        kernel.logger.INFO("Adding drive {s} {s}",
            .{@tagName(device.channel), device.name}
        );
        try self.drives.append(device);
    }

    pub fn iterate(self: *const ATAManager) Iterator {
        return Iterator{
            .drives = &self.drives,
            .current = 0,
        };
    }
};

pub var ata_manager: ATAManager = undefined;

pub fn ata_init() void {
    const temp: ?[*]u16 = kernel.mm.kmallocArray(u16, 256);
    if (temp) |buf| {
        ide_buf = buf;
    } else {
        dbg.printf("error Initializing ata\n", .{});
        return ;
    }
    @memset(ide_buf[0..256], 0);
    ata_manager = ATAManager.init();
    // Iterate over all PCI IDE Inerfaces (0x01 class = mass storage, 0x01 subclass = IDE Intereface)
    var ide_iter = pci.pci_manager.iterateByClass(0x01, 0x01);
    while (ide_iter.next()) |ide_dev| {
        if (ata_probe_channel(
            .PRIMARY_MASTER,
            ide_dev
        )) |ata_drive| {
            ata_manager.addDevice(ata_drive) catch kernel.logger.ERROR("error adding drive", .{});
        }
        if (ata_probe_channel(
            .PRIMARY_SLAVE,
            ide_dev
        )) |ata_drive| {
            ata_manager.addDevice(ata_drive) catch kernel.logger.ERROR("error adding drive", .{});
        }
        if (ata_probe_channel(
            .SECONDARY_MASTER, 
            ide_dev
        )) |ata_drive| {
            ata_manager.addDevice(ata_drive) catch kernel.logger.ERROR("error adding drive", .{});
        }
        if (ata_probe_channel(
            .SECONDARY_SLAVE,
            ide_dev
        )) |ata_drive| {
            ata_manager.addDevice(ata_drive) catch kernel.logger.ERROR("error adding drive", .{});
        }
    }
    var ata_iter = ata_manager.iterate();
    while (ata_iter.next()) |ata| {
        kernel.logger.INFO(
            "READING DRIVE {s} {s}", 
            .{@tagName(ata.channel), ata.name}
        );
        ata.read_full_drive_dma();
    }
}
