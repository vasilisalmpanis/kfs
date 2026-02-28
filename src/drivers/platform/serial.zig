const io = @import("arch").io;
const kernel = @import("kernel");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");
const pbus = @import("./bus.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

pub const MAX_SERIAL_PORTS: usize = 4;
var serial_ports: [MAX_SERIAL_PORTS]Serial = .{Serial{}} ** MAX_SERIAL_PORTS;

pub const COM_PORTS: [4]u16 = .{
    0x3F8,
    0x2F8,
    0x3E8,
    0x2E8,
};

var serial_driver = pdrv.PlatformDriver {
    .driver = drv.Driver {
        .list = undefined,
        .name = "8250",
        .probe = undefined,
        .remove = undefined,
        .fops = &serial_file_ops,
    },
    .probe = serial_probe,
    .remove = serial_remove,
};


var serial_file_ops = kernel.fs.FileOps{
    .open = serial_open,
    .close = serial_close,
    .read = serial_read,
    .write = serial_write,
    .lseek = null,
    .readdir = null,
};

fn getSerial(file: *kernel.fs.File) !*Serial {
    if (file.inode.data.dev) |_d| {
        return @ptrCast(@alignCast(_d.data));
    }
    return kernel.errors.PosixError.EIO;
}

fn serial_open(_: *kernel.fs.File, _: *kernel.fs.Inode) !void {
    kernel.logger.WARN("8250 file opened\n", .{});
}

fn serial_close(_: *kernel.fs.File) void {
}

fn serial_read(file: *kernel.fs.File, buf: [*]u8, size: usize) !usize {
    const serial = try getSerial(file);
    var i: usize = 0;
    while (i < size and serial.canRead()) {
        buf[i] = serial.getchar();
        i += 1;
    }
    return i;
}

fn serial_write(file: *kernel.fs.File, buf: [*]const u8, size: usize) !usize {
    const serial = try getSerial(file);
    const msg_slice: []const u8 = buf[0..size];
    serial.print(msg_slice);
    return size;
}


fn serial_probe(device: *pdev.PlatformDevice) !void {
    if (device.dev.data == null)
        return kernel.errors.PosixError.EIO;
    const serial: *Serial = @ptrCast(@alignCast(device.dev.data));
    serial.setup();
    try cdev.addCdev(&device.dev, kernel.fs.UMode.chardev());
}

fn serial_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
    kernel.logger.WARN("serial cannot be initialized", .{});
}

pub fn init() void {
    kernel.logger.DEBUG("DRIVER INIT Serial", .{});
    if (pdev.PlatformDevice.alloc("8250")) |serial| {
        if (kernel.mm.kmalloc(Serial)) |data| {
            if (Serial.init(COM_PORTS[0])) |_serial| {
                data.* = _serial;
            } else {
                kernel.mm.kfree(data);
                return;
            }
            serial.dev.data = @ptrCast(@alignCast(data));
        } else {
            return ;
        }
        serial.register() catch {
            return ;
        };
        kernel.logger.WARN("Device registered for serial", .{});
        pdrv.platform_register_driver(&serial_driver.driver) catch |err| {
            kernel.logger.ERROR("Error registering platform driver: {any}", .{err});
            return ;
        };
        kernel.logger.WARN("Driver registered for serial", .{});
        return ;
    }
    kernel.logger.WARN("serial cannot be initialized", .{});
}

pub fn getByIndex(idx: usize) ?*Serial {
    if (idx >= MAX_SERIAL_PORTS)
        return null;
    if (serial_ports[idx].addr == 0)
        return null;
    return &serial_ports[idx];
}

const InterruptReg = packed struct(u8) {
    data_avail:             bool = true,
    trans_holder_reg_empty: bool = false,
    receiver_line_status:   bool = false,
    modem_status:           bool = false,
    _reserve:               u4 = 0,
};

pub const Serial = struct {
    addr: u16 = 0,
    wait_queue: kernel.wq.WaitQueueHead = kernel.wq.WaitQueueHead.init(),


    pub fn init(port: u16) ?Serial {
        if (!loopbackSelfTest(port))
            return null;
        const serial = Serial{ .addr = port };
        return serial;
    }

    pub fn setup(self: *Serial) void {
        io.outb(self.addr + 1, 0x00);
        io.outb(self.addr + 3, 0x80);
        io.outb(self.addr, 0x01);
        io.outb(self.addr + 1, 0x00);
        io.outb(self.addr + 3, 0x03);
        io.outb(self.addr + 2, 0xC7);
        io.outb(self.addr + 1, 0x01);
        self.wait_queue.setup();
        self.enableInterrupt();
    }

    pub fn enableInterrupt(self: *Serial) void {
        io.outb(self.addr + 1, @bitCast(InterruptReg{}));
    }

    fn loopbackSelfTest(port: u16) bool {
        const old_lcr = io.inb(port + 3);
        const old_mcr = io.inb(port + 4);

        io.outb(port + 1, 0x00);
        io.outb(port + 3, 0x80);
        io.outb(port + 0, 0x01);
        io.outb(port + 1, 0x00);
        io.outb(port + 3, 0x03);
        io.outb(port + 4, 0x1E);

        io.outb(port + 0, 0xAE);
        const ok = io.inb(port + 0) == 0xAE;

        io.outb(port + 4, old_mcr);
        io.outb(port + 3, old_lcr);
        io.outb(port + 1, 0x00);

        return ok;
    }

    fn portIndex(port: u16) ?usize {
        for (COM_PORTS, 0..) |known_port, idx| {
            if (known_port == port)
                return idx;
        }
        return null;
    }

    pub fn hasPendingInterrupt(self: *Serial) bool {
        const iir = io.inb(self.addr + 2);
        return (iir & 0b0000_0001) == 0b0000_0000;
    }


    pub fn putchar(self: *Serial, char: u8) void {
        while ((io.inb(self.addr + 5) & 0x20) == 0) {}
        io.outb(self.addr, char);
    }

    pub fn canRead(self: *Serial) bool {
        return (io.inb(self.addr + 5) & 0x01) != 0;
    }

    pub fn getchar(self: *Serial) u8 {
        return io.inb(self.addr);
    }

    pub fn print(self: *Serial, message: []const u8) void {
        for (message) |char| {
            self.putchar(char);
        }
    }
};

fn serial_interrupt(_: ?*anyopaque) void {
    for (0..MAX_SERIAL_PORTS) |idx| {
        if (getByIndex(idx)) |ser| {
            if (ser.hasPendingInterrupt())
                ser.wait_queue.wakeUpOne();
        }
    }
}

pub fn init_ports() void {
    var kernel_set: bool = false;
    var int3_set: bool = false;
    var int4_set: bool = false;
    for (COM_PORTS, 0..) |port, idx| {
        if (Serial.init(port)) |_ser| {
            serial_ports[idx] = _ser;
            serial_ports[idx].setup();
            if (!kernel_set) {
                kernel_set = true;
                kernel.serial = serial_ports[idx];
            }
            if ((idx + 1) % 2 == 0 and !int3_set) {
                kernel.irq.registerHandler(3, serial_interrupt, null);
                int3_set = true;
            }
            if ((idx + 1) % 2 == 1 and !int4_set) {
                kernel.irq.registerHandler(4, serial_interrupt, null);
                int4_set = true;
            }
        }
    }
}
