const io = @import("arch").io;
const kernel = @import("kernel");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");
const pbus = @import("./bus.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

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

var default_serial: ?*Serial = null;

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
            data.* = Serial.init(COM1);
            default_serial = data;
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

pub fn getDefault() ?*Serial {
    return default_serial;
}

const COM1: u16 = 0x3F8;

pub const Serial = struct {
    addr: u16, // COM1
    pub fn init(port: u16) Serial {
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
