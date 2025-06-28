// Keep current drive saved 
// Only select another if we need to use another
// The suggestion is to read the Status register FIFTEEN TIMES, and only pay attention to the value returned by the last one -- after selecting a new master or slave device
const std = @import("std");
const dbg = @import("debug");
const kernel = @import("kernel");
const irq = kernel.irq;
const arch = @import("arch");
const lst = kernel.list;

const ATA_PRIMARY_IRQ:      u16 = 14;
const ATA_SECONDARY_IRQ:    u16 = 15;
const ATA_PRIMARY_IO:       u16 = 0x1F0;
const ATA_SECONDARY_IO:     u16 =  0x170;

const ATA_PRIMARY_STATUS    = 0x3F6;
const ATA_SECONDARY_STATUS  = 0x376;

const BMIDE_PRIMARY_REG     = 0xC000;
const BMIDE_SECONDARY_REG   = 0xC00F;

const BMIDE_COMMAND     = 0x00;
const BMIDE_STATUS      = 0x01;
const BMIDE_RESERVED    = 0x02;
const BMIDE_PRDT_ADDR   = 0x04;

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

var channels: ?*PataChannel = null;

const PataChannel = struct {
    name: [41]u8,

    io_base: u16,
    irq_num: u32,

    current_op: ATA_Operation   = .ATA_OP_NONE,
    status:     ATA_Status      = .ATA_STATUS_IDLE,
    device_cmd: u8,

    buffer: [*]u8 = undefined,
    buffer_size: u32 = 512,

    lba28: u32 = 0,
    lba48: u64 = 0,
    sector_count: u8,
    drive: u8,

    irq_enabled: bool = false,

    list: lst.ListHead,

    fn add(io_base: u16, irq_num: u32, name: [41]u8) ?*PataChannel {
        const new_channel: ?*PataChannel = kernel.mm.kmalloc(PataChannel);
        if (new_channel) |channel| {
            channel.buffer_size = 512 * 256;
            channel.status = .ATA_STATUS_IDLE;
            channel.current_op = .ATA_OP_NONE;
            if (kernel.mm.kmallocArray(u8, channel.buffer_size)) |array| {
                channel.buffer = array;
            } else {
                kernel.mm.kfree(channel);
                return null;
            }

            channel.device_cmd = if (io_base == ATA_PRIMARY_IO) 0xE0 else 0xF0;
            channel.io_base = io_base;
            channel.irq_num = irq_num;
            channel.list.setup();
            channel.irq_enabled = false;
            @memset(channel.name[0..41],0);
            @memcpy(channel.name[0..41], name[0..41]);
            if (channels) |head| {
                head.list.add(&channel.list);
            } else {
                channels = channel;
            }
            channel.lba28 = @as(*u32, @ptrCast(@alignCast(&ide_buf[60]))).*;
            channel.lba48 = @as(*u64, @ptrCast(@alignCast(&ide_buf[100]))).*;
        }
        return new_channel;
    }

    fn delay(self: *PataChannel) void {
        for (0..4) |_| {
            _ = self.ata_read_reg(ATA_REG_ALTSTATUS);
        }
    }

    fn poll_ide(self: *PataChannel) void {
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

    fn read_sectors(self: *PataChannel, lba: u32, num_sectors: u8) []const u8 {
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

    fn read_sectors_dma(self: *PataChannel, lba: u32, num_sectors: u8) void {
        const device_cmd: u8 = self.device_cmd | @as(u8, @truncate((lba >> 24) & 0x0F));
        self.ata_write_reg(ATA_REG_SECCOUNT0, num_sectors);
        self.ata_write_reg(ATA_REG_LBA0, @truncate(lba));
        self.ata_write_reg(ATA_REG_LBA1, @truncate(lba >> 8));
        self.ata_write_reg(ATA_REG_LBA2, @truncate(lba >> 16));
        self.ata_write_reg(ATA_REG_HDDEVSEL, device_cmd);
        self.ata_write_reg(ATA_REG_COMMAND, ATA_CMD_READ_DMA);
        arch.io.outb(BMIDE_PRIMARY_REG + BMIDE_COMMAND, 0x01);
        self.poll_ide();
        // const sectors: u32 = if (num_sectors == 0) 256 else num_sectors;
        self.delay();
        return;
    }

    inline fn ata_write_reg(channel: *PataChannel, reg: u8, value: u8) void {
        arch.io.outb(channel.io_base + reg, value);
    }

    inline fn ata_read_reg(channel: *PataChannel, reg: u8) u8 {
        return arch.io.inb(channel.io_base + reg);
    }

    pub fn read_full_drive(self: *PataChannel) void {
        const num_sec: u32 = 1;
        for (0..self.lba28 / num_sec) |i| {
            const lba = i * num_sec;
            const sector = self.read_sectors(lba, num_sec);
            if (!std.mem.allEqual(u8, sector, 0)) {
                kernel.logger.INFO("{d}: {s}", .{ lba, sector });
            }
        }
    }

    pub fn read_full_drive_dma(self: *PataChannel) void {
        const num_sec: u32 = 1;
        for (0..7) |i| {
            const lba = i * num_sec;
            self.read_sectors_dma(lba, num_sec);
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            self.poll_ide();
            kernel.logger.INFO("{d}: {s}", .{ lba, dma[0..512] });
        }
    }
};

var ide_buf: [*]u16 = undefined;

pub fn ata_primary() void {
    kernel.logger.DEBUG("primary\n", .{});
}

pub fn ata_secondary() void {
    kernel.logger.DEBUG("secondary\n", .{});
}

fn ide_select_drive(bus: u8, i: u8) void {
	if(bus == ATA_PRIMARY) {
        if(i == ATA_MASTER) {
            arch.io.outb(ATA_PRIMARY_IO + ATA_REG_HDDEVSEL, 0xA0);
        } else {
            arch.io.outb(ATA_PRIMARY_IO + ATA_REG_HDDEVSEL, 0xB0);
        }
    } else {
        if(i == ATA_MASTER) {
            arch.io.outb(ATA_SECONDARY_IO + ATA_REG_HDDEVSEL, 0xA0);
        } else {
            arch.io.outb(ATA_SECONDARY_IO + ATA_REG_HDDEVSEL, 0xB0);
        }
    }
}

fn ata_identify(bus: u8, drive: u8) u8 {
    var io: u16 = 0; 
    if(bus == ATA_PRIMARY) {
        io = ATA_PRIMARY_IO;
    } else {
        io = ATA_SECONDARY_IO;
    }
    // Check if any drive present and ready
    var status = arch.io.inb(io + ATA_REG_STATUS);
    if (status == 0 or status == 0xFF) {
        return 0;
    }
    ide_select_drive(bus, drive);
    // ATA specs say these values must be zero before sending IDENTIFY */
    arch.io.outb(io + ATA_REG_SECCOUNT0, 0);
    arch.io.outb(io + ATA_REG_LBA0, 0);
    arch.io.outb(io + ATA_REG_LBA1, 0);
    arch.io.outb(io + ATA_REG_LBA2, 0);
    // Now, send IDENTIFY */
    arch.io.outb(io + ATA_REG_COMMAND, ATA_CMD_IDENTIFY);
    // Now, poll untill BSY is clear. */
    while(arch.io.inb(io + ATA_REG_STATUS) & ATA_SR_BSY != 0) {}
    status = arch.io.inb(io + ATA_REG_STATUS);
    while(!(status & ATA_SR_DRQ != 0)) {
        if(status & ATA_SR_ERR != 0)
        {
            kernel.logger.ERROR("ERROR bus {d}, drive {d}\n", .{bus, drive});
            return 0;
        }
        status = arch.io.inb(io + ATA_REG_STATUS);
    }
    for(0..256) |i| {
        ide_buf[i] = arch.io.inw(io + ATA_REG_DATA);
    }
    irq.registerHandler(
        if (bus == ATA_PRIMARY) ATA_PRIMARY_IRQ else ATA_SECONDARY_IRQ,
        if (bus == ATA_PRIMARY) ata_primary else ata_secondary
    );
    return 1;
}

fn ata_probe_channel(bus: u8, channel: u8) void {
    var str: [41]u8 = .{0} ** 41;
    const io: u16 = if (bus == ATA_PRIMARY) ATA_PRIMARY_IO else ATA_SECONDARY_IO;
    if(ata_identify(bus, channel) != 0)
    {
        for (0..20) |i| {
            const word_idx = ATA_IDENT_MODEL / 2 + i;
            const word = ide_buf[word_idx];

            str[i * 2] = @truncate(word >> 8);
            str[i * 2 + 1] = @truncate(word & 0xFF);
        }
        if (PataChannel.add(io, 14, str)) |_channel| {
            kernel.logger.WARN("ide name {s} {any}\n", .{_channel.name, _channel});
        }
    }
}

const PRDEntry = struct {
    phys: u32,
    size: u16,
    flags: u16,
};

var dma: [*]u8 = undefined;

fn alloc_prdt() u32 {
    const phys = kernel.mm.virt_memory_manager.pmm.allocPage();
    const virt: u32 = 0xE0000000;
    kernel.mm.virt_memory_manager.mapPage(virt, phys, .{});
    @memset(@as([*]u8, @ptrFromInt(virt))[0..4096], 0);
    dma = @ptrFromInt(virt + @sizeOf(PRDEntry));
    const prde: *PRDEntry = @ptrFromInt(virt);
    prde.phys = phys + @sizeOf(PRDEntry);
    prde.size = 512 * 7;
    prde.flags = 0x8000;
    return phys;
}

fn init_dma() void {
    const prde_addr = alloc_prdt();
    arch.io.outb(BMIDE_PRIMARY_REG + BMIDE_STATUS, 0x10);
    arch.io.outb(BMIDE_PRIMARY_REG + BMIDE_COMMAND, 0x00);
    arch.io.outl(BMIDE_PRIMARY_REG + BMIDE_PRDT_ADDR, prde_addr);
    const status = arch.io.inb(BMIDE_PRIMARY_REG + BMIDE_STATUS);
    kernel.logger.INFO("BMI status: {x}", .{status});
    arch.io.outb(BMIDE_PRIMARY_REG + BMIDE_STATUS, status & 0xFC);
}

fn ata_probe() void {
    ata_probe_channel(ATA_PRIMARY, ATA_MASTER);
    // ata_probe_channel(ATA_PRIMARY, ATA_SLAVE);
    // ata_probe_channel(ATA_SECONDARY, ATA_MASTER);
    // ata_probe_channel(ATA_SECONDARY, ATA_SLAVE);
}

pub fn ata_init() void {
    if (@import("../../pci.zig").getDevice(0x01, 0x01)) |ide_device| {
        kernel.logger.INFO("FOUND IDE DEVICE", .{});
        ide_device.print();
    }
    const temp: ?[*]u16 = kernel.mm.kmallocArray(u16, 256);
    if (temp) |buf| {
        ide_buf = buf;
    } else {
        dbg.printf("error Initializing ata\n", .{});
        return ;
    }
    @memset(ide_buf[0..256], 0);
    dbg.printf("Initializing ATA device\n", .{});
    ata_probe();
    init_dma();
    // kernel.logger.INFO("{any}", .{channels});
    channels.?.read_full_drive_dma();
}
