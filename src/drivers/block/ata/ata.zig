const dbg = @import("debug");
const kernel = @import("kernel");
const irq = kernel.irq;
const arch = @import("arch");
const lst = kernel.list;

const ATA_PRIMARY_IRQ:      u16 = 14;
const ATA_SECONDARY_IRQ:    u16 = 15;
const ATA_PRIMARY_IO:       u16 = 0x1F0;
const ATA_SECONDARY_IO:     u16 =  0x170;

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

const ATA_REG_DATA        = 0x00;
const ATA_REG_ERROR       = 0x01;
const ATA_REG_FEATURES    = 0x01;
const ATA_REG_SECCOUNT0   = 0x02;
const ATA_REG_LBA0        = 0x03;
const ATA_REG_LBA1        = 0x04;
const ATA_REG_LBA2        = 0x05;
const ATA_REG_HDDEVSEL    = 0x06;
const ATA_REG_COMMAND     = 0x07;
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

    buffer: [*]u8 = undefined,
    buffer_size: u32 = 512,

    lba: u32,
    sector_count: u8,
    drive: u8,

    irq_enabled: bool = false,

    list: lst.ListHead,

    fn add(io_base: u16, irq_num: u32, name: [41]u8) ?*PataChannel {
        const new_channel: ?*PataChannel = kernel.mm.kmalloc(PataChannel);
        if (new_channel) |channel| {
            channel.buffer_size = 512;
            if (kernel.mm.kmallocArray(u8, channel.buffer_size)) |array| {
                channel.buffer = array;
            } else {
                kernel.mm.kfree(channel);
                return null;
            }

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
        }
        return new_channel;
    }

    inline fn ata_write_reg(channel: *PataChannel, reg: u8, value: u8) void {
        arch.io.outb(channel.io_base + reg, value);
    }
    inline fn ata_read_reg(channel: *PataChannel, reg: u8) u8 {
        return arch.io.inb(channel.io_base + reg);
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
        }
        else {
            if(i == ATA_MASTER) {
                arch.io.outb(ATA_SECONDARY_IO + ATA_REG_HDDEVSEL, 0xA0);
            } else {
                arch.io.outb(ATA_SECONDARY_IO + ATA_REG_HDDEVSEL, 0xB0);
            }
        }
}

fn ata_identify(bus: u8, drive: u8) u8 {
   var io: u16 = 0; 
   ide_select_drive(bus, drive);
   if(bus == ATA_PRIMARY) {
       io = ATA_PRIMARY_IO;
   } else {
       io = ATA_SECONDARY_IO;
   }
   // ATA specs say these values must be zero before sending IDENTIFY */
   arch.io.outb(io + ATA_REG_SECCOUNT0, 0);
   arch.io.outb(io + ATA_REG_LBA0, 0);
   arch.io.outb(io + ATA_REG_LBA1, 0);
   arch.io.outb(io + ATA_REG_LBA2, 0);

   // Now, send IDENTIFY */
   arch.io.outb(io + ATA_REG_COMMAND, ATA_CMD_IDENTIFY);

   // Now, read status port */
   var status: u8 = arch.io.inb(io + ATA_REG_STATUS);
   if(status != 0)
   {
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
           ide_buf[i*2] = arch.io.inw(io + ATA_REG_DATA);
       }
   }
   return 1;
}

fn ata_probe_channel(bus: u8, channel: u8) void {
    var str: [41]u8 = .{0} ** 41;
    const io: u16 = if (bus == ATA_PRIMARY) ATA_PRIMARY_IO else ATA_SECONDARY_IO;
    if(ata_identify(bus, channel) != 0)
    {
        for (0..20) |i| {
            const word_idx = ATA_IDENT_MODEL + i;
            const word = ide_buf[word_idx];

            str[i * 2] = @truncate(word >> 8);
            str[i * 2 + 1] = @truncate(word & 0xFF);
        }
        if (PataChannel.add(io, 14, str)) |_channel| {
            kernel.logger.WARN("ide name {s}\n", .{_channel.name});
        }
    }
}

fn ata_probe() void {
    ata_probe_channel(ATA_PRIMARY, ATA_MASTER);
    ata_probe_channel(ATA_PRIMARY, ATA_SLAVE);
    ata_probe_channel(ATA_SECONDARY, ATA_MASTER);
    ata_probe_channel(ATA_SECONDARY, ATA_SLAVE);
}

pub fn ata_init() void {
    const temp: ?[*]u16 = kernel.mm.kmallocArray(u16, 256);
    if (temp) |buf| {
        ide_buf = buf;
    } else {
        dbg.printf("error Initializing ata\n", .{});
        return ;
    }
    @memset(ide_buf[0..256], 0);
    dbg.printf("Initializing ATA device\n", .{});
    irq.registerHandler(ATA_PRIMARY_IRQ, ata_primary);
    irq.registerHandler(ATA_SECONDARY_IRQ, ata_secondary);
    ata_probe();
}
