const drv = @import("../main.zig");
const pci = drv.pci;
const kernel = @import("kernel");
const arch = @import("arch");
const std = @import("std");

const REG_CTRL: u16       =  0x0000;
const REG_STATUS: u16     =  0x0008;
const REG_EEPROM: u16     =  0x0014;
const REG_CTRL_EXT: u16   =  0x0018;
const REG_IMASK: u16      =  0x00D0;
const REG_ICR: u16        =  0x00C0;
const REG_IMC: u16        =  0x00D8;

const INT_LSC: u32        =  1 << 2;
const INT_RXDMT0: u32     =  1 << 4;
const INT_RXO: u32        =  1 << 6;
const INT_RXT0: u32       =  1 << 7;
const INT_MASK: u32       = INT_LSC | INT_RXDMT0 | INT_RXO | INT_RXT0;

const REG_RCTRL: u16      =  0x0100;
const REG_RXDESCLO: u16   =  0x2800;
const REG_RXDESCHI: u16   =  0x2804;
const REG_RXDESCLEN: u16  =  0x2808;
const REG_RXDESCHEAD: u16 =  0x2810;
const REG_RXDESCTAIL: u16 =  0x2818;

const REG_TCTRL: u16      =  0x0400;
const REG_TXDESCLO: u16   =  0x3800;
const REG_TXDESCHI: u16   =  0x3804;
const REG_TXDESCLEN: u16  =  0x3808;
const REG_TXDESCHEAD: u16 =  0x3810;
const REG_TXDESCTAIL: u16 =  0x3818;

const REG_RDTR: u16        =  0x2820; // RX Delay Timer Register
const REG_RXDCTL: u16      =  0x2828; // RX Descriptor Control
const REG_RADV: u16        =  0x282C; // RX Int. Absolute Delay Timer
const REG_RSRPD: u16       =  0x2C00; // RX Small Packet Detect Interrupt

const REG_TIPG: u16        =  0x0410;      // Transmit Inter Packet Gap
const ECTRL_SLU: u16       =  0x40;        //set link up

const RCTL_EN: u32                         = (1 << 1);    // Receiver Enable
const RCTL_SBP: u32                        = (1 << 2);    // Store Bad Packets
const RCTL_UPE: u32                        = (1 << 3);    // Unicast Promiscuous Enabled
const RCTL_MPE: u32                        = (1 << 4);    // Multicast Promiscuous Enabled
const RCTL_LPE: u32                        = (1 << 5);    // Long Packet Reception Enable
const RCTL_LBM_NONE: u32                   = (0 << 6);    // No Loopback
const RCTL_LBM_PHY: u32                    = (3 << 6);    // PHY or external SerDesc loopback
const RTCL_RDMTS_HALF: u32                 = (0 << 8);    // Free Buffer Threshold is 1/2 of RDLEN
const RTCL_RDMTS_QUARTER: u32              = (1 << 8);    // Free Buffer Threshold is 1/4 of RDLEN
const RTCL_RDMTS_EIGHTH: u32               = (2 << 8);    // Free Buffer Threshold is 1/8 of RDLEN
const RCTL_MO_36: u32                      = (0 << 12);   // Multicast Offset - bits 47:36
const RCTL_MO_35: u32                      = (1 << 12);   // Multicast Offset - bits 46:35
const RCTL_MO_34: u32                      = (2 << 12);   // Multicast Offset - bits 45:34
const RCTL_MO_32: u32                      = (3 << 12);   // Multicast Offset - bits 43:32
const RCTL_BAM: u32                        = (1 << 15);   // Broadcast Accept Mode
const RCTL_VFE: u32                        = (1 << 18);   // VLAN Filter Enable
const RCTL_CFIEN: u32                      = (1 << 19);   // Canonical Form Indicator Enable
const RCTL_CFI: u32                        = (1 << 20);   // Canonical Form Indicator Bit Value
const RCTL_DPF: u32                        = (1 << 22);   // Discard Pause Frames
const RCTL_PMCF: u32                       = (1 << 23);   // Pass MAC Control Frames
const RCTL_SECRC: u32                      = (1 << 26);   // Strip Ethernet CRC

// Buffer Sizes
const RCTL_BSIZE_256: u32                  = (3 << 16);
const RCTL_BSIZE_512: u32                  = (2 << 16);
const RCTL_BSIZE_1024: u32                 = (1 << 16);
const RCTL_BSIZE_2048: u32                 = (0 << 16);
const RCTL_BSIZE_4096: u32                 = ((3 << 16) | (1 << 25));
const RCTL_BSIZE_8192: u32                 = ((2 << 16) | (1 << 25));
const RCTL_BSIZE_16384: u32                = ((1 << 16) | (1 << 25));

// Transmit Command
const CMD_EOP: u16                         = (1 << 0);    // End of Packet
const CMD_IFCS: u16                        = (1 << 1);    // Insert FCS
const CMD_IC: u16                          = (1 << 2);    // Insert Checksum
const CMD_RS: u16                          = (1 << 3);    // Report Status
const CMD_RPS: u16                         = (1 << 4);    // Report Packet Sent
const CMD_VLE: u16                         = (1 << 6);    // VLAN Packet Enable
const CMD_IDE: u16                         = (1 << 7);    // Interrupt Delay Enable

// TCTL Register
const TCTL_EN: u32                         = (1 << 1);    // Transmit Enable
const TCTL_PSP: u32                        = (1 << 3);    // Pad Short Packets
const TCTL_CT_SHIFT: u32                   = 4;           // Collision Threshold
const TCTL_COLD_SHIFT: u32                 = 12;          // Collision Distance
const TCTL_SWXOFF: u32                     = (1 << 22);   // Software XOFF Transmission
const TCTL_RTLC: u32                       = (1 << 24);   // Re-transmit on Late Collision

const TSTA_DD: u16                         = (1 << 0);    // Descriptor Done
const TSTA_EC: u16                         = (1 << 1);    // Excess Collisions
const TSTA_LC: u16                         = (1 << 2);    // Late Collision
const LSTA_TU: u16                         = (1 << 3);    // Transmit Underrun

const E1000_NUM_RX_DESC: u32 = 32;
const E1000_NUM_TX_DESC: u32 = 8;

const E1000RxDesc = extern struct {
    addr:       u64 = 0,
    len:        u16 = 0,
    checksum:   u16 = 0,
    status:     u8 = 0,
    errors:     u8 = 0,
    special:    u16 = 0,
};

const E1000TxDesc = extern struct {
    addr:       u64 = 0,
    len:        u16 = 0,
    cso:        u8 = 0,
    cmd:        u8 = 0,
    status:     u8 = 0,
    css:        u8 = 0,
    special:    u16 = 0,
};

const DmaMemory = struct {
    phys:   u32,
    virt:   usize,
    pages:  u32,

    fn alloc(pages: u32) !DmaMemory {
        const state = kernel.mm.mem_lock.lock_irq_disable();
        defer kernel.mm.mem_lock.unlock_irq_enable(state);

        const pmm = kernel.mm.virt_memory_manager.pmm;
        const phys = pmm.allocPages(pages);
        if (phys == 0)
            return kernel.errors.PosixError.ENOMEM;
        errdefer for (0..pages) |i| {
            pmm.freePage(phys + i * kernel.mm.PAGE_SIZE);
        };

        const virt = try kernel.mm.mapPhys(phys, pages, .{});
        const bytes: [*]u8 = @ptrFromInt(virt);
        @memset(bytes[0..pages * kernel.mm.PAGE_SIZE], 0);
        return .{
            .phys = phys,
            .virt = virt,
            .pages = pages
        };
    }

    fn free(self: DmaMemory) void {
        const state = kernel.mm.mem_lock.lock_irq_disable();
        defer kernel.mm.mem_lock.unlock_irq_enable(state);

        for (0..self.pages) |i| {
            kernel.mm.virt_memory_manager.unmapPage(
                self.virt + i * kernel.mm.PAGE_SIZE, true,
            );
        }
    }
};

pub const E1000Device = struct {
    mem:            [*]volatile u32,
    mem_base:       u32,
    mem_size:       u32,
    io_base:        u32,
    int_line:       u8,
    eeprom_exists:  bool = false,
    mac:            [6]u8 = @splat(0),
    rxtx_mem:       ?DmaMemory = null,
    rx_buffers:     [E1000_NUM_RX_DESC]?DmaMemory = @splat(null),
    rx_descs:       [*]volatile E1000RxDesc,
    tx_descs:       [*]volatile E1000TxDesc,
    worker_thread:  ?*kernel.task.Task = null,
    wait_queue:     kernel.wq.WaitQueueHead = kernel.wq.WaitQueueHead.init(),
    rx_curr:        u8 = 0,
    tx_curr:        u8 = 0,

    fn writeCommand(self: *E1000Device, reg: u16, command: u32) void {
        self.mem[reg / 4] = command;
    }

    fn readCommand(self: *E1000Device, reg: u16) u32 {
        return self.mem[reg / 4];
    }

    fn isEEPROMPresent(self: *E1000Device) bool {
        var val: u32 = 0;

        self.writeCommand(REG_EEPROM, 0x1);
        for (0..1000) |_| {
            val = self.readCommand(REG_EEPROM);
            if (val & 0x10 != 0)
                return true;
        }
        return false;
    }

    fn eepromRead(self: *E1000Device, addr: u8) u32 {
        var tmp: u32 = 0;
        if (self.eeprom_exists) {
            self.writeCommand(
                REG_EEPROM,
                (@as(u32, addr) << @as(u8, 8)) | @as(u32, 1)
            );
            while ((tmp & (1 << 4)) == 0) {
                tmp = self.readCommand(REG_EEPROM);
            }
        }
        return (tmp >> 16) & 0xFFFF;
    }

    fn retrieveMAC(self: *E1000Device) void {
        if (self.eeprom_exists) {
            var tmp: u32 = 0;
            tmp = self.eepromRead(0);
            self.mac[0] = @intCast(tmp & 0xFF);
            self.mac[1] = @intCast(tmp >> 8);
            tmp = self.eepromRead(1);
            self.mac[2] = @intCast(tmp & 0xFF);
            self.mac[3] = @intCast(tmp >> 8);
            tmp = self.eepromRead(2);
            self.mac[4] = @intCast(tmp & 0xFF);
            self.mac[5] = @intCast(tmp >> 8);
        } else {
            const mem_base_mac_8: [*] volatile u8 = @ptrCast(&self.mem[0x5400 / 4]);
            const mem_base_mac_32: [*] volatile u32 = @ptrCast(&self.mem[0x5400 / 4]);
            if (mem_base_mac_32[0] != 0) {
                @memcpy(self.mac[0..6], mem_base_mac_8[0..6]);
            }
        }
    }

    fn enableInterrupt(self: *E1000Device) void {
        _ = self.readCommand(REG_ICR);
        self.writeCommand(REG_IMASK, INT_MASK);
        _ = self.readCommand(REG_STATUS);
    }

    fn rxInit(self: *E1000Device) !void {
        for (0..E1000_NUM_RX_DESC) |i| {
            const buffer = try DmaMemory.alloc(8192 / kernel.mm.PAGE_SIZE);
            self.rx_buffers[i] = buffer;
            self.rx_descs[i].addr = buffer.phys;
            self.rx_descs[i].status = 0;
        }
        self.writeCommand(REG_RXDESCLO, self.rxtx_mem.?.phys);
        self.writeCommand(REG_RXDESCHI, 0);
        self.writeCommand(
            REG_RXDESCLEN,
            @sizeOf(E1000RxDesc) * E1000_NUM_RX_DESC
        );
        self.writeCommand(REG_RXDESCHEAD, 0);
        self.writeCommand(REG_RXDESCTAIL, E1000_NUM_RX_DESC - 1);
        self.writeCommand(
            REG_RCTRL,
            RCTL_UPE | RCTL_MPE |
            RCTL_LBM_NONE | RTCL_RDMTS_HALF | RCTL_BAM | RCTL_SECRC |
            RCTL_BSIZE_8192
        );
    }

    fn txInit(self: *E1000Device) void {
        for (0..E1000_NUM_TX_DESC) |i| {
            self.tx_descs[i].addr = 0;
            self.tx_descs[i].cmd = 0;
            self.tx_descs[i].status = TSTA_DD;
        }
        self.writeCommand(
            REG_TXDESCLO,
            self.rxtx_mem.?.phys + @sizeOf(E1000RxDesc) * E1000_NUM_RX_DESC
        );
        self.writeCommand(REG_TXDESCHI, 0);
        self.writeCommand(
            REG_TXDESCLEN,
            @sizeOf(E1000TxDesc) * E1000_NUM_TX_DESC
        );
        self.writeCommand(REG_TXDESCHEAD, 0);
        self.writeCommand(REG_TXDESCTAIL, 0);
        self.writeCommand(
            REG_TCTRL,
            TCTL_PSP |
            (15 << TCTL_CT_SHIFT) | (64 << TCTL_COLD_SHIFT) |
            TCTL_RTLC
        );
        self.writeCommand(REG_TIPG, 0x0060_200A);
    }

    pub fn new(
        mem_base: u32,
        mem_size: u32,
        io_base: u32,
        int_line: u8
    ) !*E1000Device {
        const dev = kernel.mm.kmalloc(E1000Device) orelse
            return kernel.errors.PosixError.ENOMEM;
        errdefer kernel.mm.kfree(dev);
        var pages: u32 = mem_size / kernel.mm.PAGE_SIZE;

        if (!arch.isPageAligned(mem_size))
            pages += 1;
        const mapped: u32 = blk: {
            const state = kernel.mm.mem_lock.lock_irq_disable();
            defer kernel.mm.mem_lock.unlock_irq_enable(state);

            break :blk try kernel.mm.mapPhys(
                mem_base,
                pages,
                .{ .present = true, .writable = true, .cache_disable = true}
            );
        };
        dev.* = E1000Device{
            .mem = @ptrFromInt(mapped),
            .mem_base = mem_base,
            .io_base = io_base,
            .mem_size = mem_size,
            .int_line = int_line,
            .rx_descs = undefined,
            .tx_descs = undefined,
        };
        dev.wait_queue.setup();
        return dev;
    }

    pub fn deinit(self: *E1000Device) void {
        self.writeCommand(REG_IMC, 0xFFFF_FFFF);
        self.writeCommand(REG_RCTRL, 0);
        self.writeCommand(REG_TCTRL, 0);
        _ = self.readCommand(REG_STATUS);

        for (self.rx_buffers) |buffer| {
            if (buffer) |dma|
                dma.free();
        }
        if (self.rxtx_mem) |dma|
            dma.free();

        const state = kernel.mm.mem_lock.lock_irq_disable();
        const pages = (self.mem_size + kernel.mm.PAGE_SIZE - 1) / kernel.mm.PAGE_SIZE;
        for (0..pages) |i| {
            kernel.mm.virt_memory_manager.unmapPage(
                @intFromPtr(self.mem) + i * kernel.mm.PAGE_SIZE, false
            );
        }
        kernel.mm.mem_lock.unlock_irq_enable(state);
        kernel.mm.kfree(self);
    }

    fn handleReceive(self: *E1000Device) void {
        while (self.rx_descs[self.rx_curr].status & 0x1 != 0) {
            const len: u16 = self.rx_descs[self.rx_curr].len;
            if (self.rx_descs[self.rx_curr].errors == 0 and
                self.rx_descs[self.rx_curr].status & 0x2 != 0 and len <= 8192)
            {
                const buf: [*]const u8 = @ptrFromInt(
                    self.rx_buffers[self.rx_curr].?.virt
                );
                if (len < 6) {
                    kernel.logger.INFO("Got packet with len {d}", .{len});
                } else {
                    kernel.logger.INFO(
                        \\
                        \\ Got ethernet packet
                        \\   len: {d}
                        \\   dest: {x}:{x}:{x}:{x}:{x}:{x}
                        \\
                        ,.{
                            len,
                            buf[0], buf[1], buf[2], buf[3], buf[4], buf[5]
                        }
                    );
                }
            }

            self.rx_descs[self.rx_curr].status = 0;
            const old_cur: u32 = self.rx_curr;
            self.rx_curr = (self.rx_curr + 1) % @as(u8, @truncate(E1000_NUM_RX_DESC));
            self.writeCommand(REG_RXDESCTAIL, old_cur);
        }
    }

    fn handleEvent(self: *E1000Device) void {
        const status: u32 = self.readCommand(REG_ICR);
        if (status == 0)
            return;
        kernel.logger.INFO("e1000 ICR: 0x{x}", .{status});
        if (status & INT_LSC != 0) {
            kernel.logger.INFO(
                "e1000 link up: {any}",
                .{self.readCommand(REG_STATUS) & 2 != 0}
            );
            // TODO: handle link up
        }
        if (status & INT_RXO != 0) {
            kernel.logger.INFO("e1000 receive overrun", .{});
        }
        if (status & (INT_RXDMT0 | INT_RXO | INT_RXT0) != 0)
            self.wait_queue.wakeUpOne();
    }

    pub fn intHandler(arg: ?*anyopaque) callconv(.c) void {
        const self: *E1000Device = @ptrCast(@alignCast(arg.?));
        self.handleEvent();
    }

    pub fn init(self: *E1000Device) void {
        self.writeCommand(REG_IMC, 0xFFFF_FFFF);
        self.writeCommand(REG_RCTRL, 0);
        self.writeCommand(REG_TCTRL, 0);
        _ = self.readCommand(REG_STATUS);
        self.eeprom_exists = self.isEEPROMPresent();
        self.retrieveMAC();
        kernel.logger.INFO(
            "EEPROM: {any}, MAC addr: {x}:{x}:{x}:{x}:{x}:{x}",
            .{
                self.eeprom_exists,
                self.mac[0], self.mac[1], self.mac[2],
                self.mac[3], self.mac[4], self.mac[5],
            }
        );
    }

    pub fn up(self: *E1000Device) !void {
        @memset(self.mem[0x5200 / 4 .. 0x5400 / 4], 0);
        self.rxtx_mem = try DmaMemory.alloc(1);
        self.rx_descs = @ptrFromInt(self.rxtx_mem.?.virt);
        self.tx_descs = @ptrFromInt(
            self.rxtx_mem.?.virt + @sizeOf(E1000RxDesc) * E1000_NUM_RX_DESC
        );
        self.writeCommand(
            REG_CTRL,
            self.readCommand(REG_CTRL) | ECTRL_SLU
        );
        try self.rxInit();
        self.txInit();
        try kernel.irq.registerPCIHandler(
            self.int_line,
            E1000Device.intHandler,
            self
        );
        self.enableInterrupt();
        self.writeCommand(
            REG_RCTRL,
            self.readCommand(REG_RCTRL) | RCTL_EN
        );
        self.writeCommand(
            REG_TCTRL,
            self.readCommand(REG_TCTRL) | TCTL_EN
        );
        _ = self.readCommand(REG_STATUS);
        kernel.logger.INFO("e1000 ready, IRQ {d}", .{self.int_line});
    }

    pub fn sendPacket(self: *E1000Device, p_data: u32, p_len: u16) void {
        self.tx_descs[self.tx_curr].addr = p_data;
        self.tx_descs[self.tx_curr].len = p_len;
        self.tx_descs[self.tx_curr].cmd = CMD_EOP | CMD_IFCS | CMD_RS;
        self.tx_descs[self.tx_curr].status = 0;
        const old_cur: u32 = self.tx_curr;
        self.tx_curr = (self.tx_curr + 1) % @as(u8, E1000_NUM_TX_DESC);
        self.writeCommand(REG_TXDESCTAIL, self.tx_curr);
        while ((self.tx_descs[old_cur].status & TSTA_DD) == 0) {}
    }
};

var e1000_driver = pci.PCIDriver{
    .driver = drv.driver.Driver{
        .fops = null,
        .list = undefined,
        .name = "e1000",
        .probe = undefined,
        .remove = undefined,
    },
    .ids = ids,
    .probe = e1000_probe,
    .remove = e1000_remove,
};

const ids: [] const pci.driver.PCIid = &[_]pci.driver.PCIid{
    pci.driver.PCIid{
       .class = 0x2,
       .subclass = 0x0,
       .deviceid = 0x100E,
       .vendorid = 0x8086,
    },
};

fn e1000_probe(device: *pci.PCIDevice) !void {
    const command = device.read(pci.device.PCI_COMMAND) & 0xFFFF;
    device.write(
        pci.device.PCI_COMMAND,
        // Enable memory space (bit 1) and bus mastering (bit 2), clear INTx disable (bit 10).
        (command | 0x6) & ~@as(u32, 1 << 10)
    );
    errdefer device.write(pci.device.PCI_COMMAND, command);

    const mem_base: u32 = device.bar0 & 0xFFFF_FFF0;
    const io_base: u32 = device.bar1 & 0xFFFF_FFFC;
    const mem_size = device.getBarSize(pci.device.PCI_BAR0);
    var dev = try E1000Device.new(
        mem_base,
        mem_size,
        io_base,
        device.int_line
    );
    errdefer dev.deinit();
    dev.init();
    device.dev.data = dev;

    const net_dev = kernel.net.dev.NetDevice.new(
        "eth0",
        dev.mac,
        &e1000_ops
    ) orelse
        return kernel.errors.PosixError.ENOMEM;

    // TODO implement real deinit not just kfree
    errdefer kernel.mm.kfree(net_dev);
    net_dev.priv = dev;
    net_dev.flags = kernel.net.intf.IFF_BROADCAST | kernel.net.intf.IFF_MULTICAST;

    const worker_thread = try kernel.kthreadCreate(
        &e1000_kthread,
        dev,
        @ptrCast(&net_dev.name),
    );
    dev.worker_thread = worker_thread;
    try kernel.net.dev.register(net_dev);
}

fn e1000_remove(_: *pci.PCIDevice) !void {
}

fn e1000_kthread(data: ?*const anyopaque) i32 {
    kernel.logger.INFO("Hello from e1000 thread\n", .{});
    const nic: *E1000Device = @ptrCast(@alignCast(@constCast(data.?)));

    while (!kernel.task.current().should_stop) {
        nic.wait_queue.wait(false, 0);
        nic.handleReceive();
    }
    return 0;
}

/// Net Device Operations

fn e1000_up(net_dev: *kernel.net.dev.NetDevice) !void {
    const e1000: *E1000Device = @ptrCast(@alignCast(net_dev.priv));
    try e1000.up();
}

fn e1000_xmit(net_dev: *kernel.net.dev.NetDevice, dma_addr: u32, len: u16) !void {
    const e1000: *E1000Device = @ptrCast(@alignCast(net_dev.priv));
    e1000.sendPacket(dma_addr, len);
}

const e1000_ops = kernel.net.dev.NetDeviceOps{
    .up     = e1000_up,
    .xmit   = e1000_xmit,
};

pub fn init() void {
    kernel.logger.DEBUG("DRIVER INIT e1000", .{});
    pci.driver.pci_register_driver(&e1000_driver.driver) catch {
        kernel.logger.ERROR("e1000 NIC driver cannot be registered\n", .{});
    };
}
