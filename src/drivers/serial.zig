const io = @import("arch").io;
const platform = @import("buses/platform.zig");
const drv = @import("driver.zig");
const kernel = @import("kernel");
const cdev = @import("./cdev.zig");

var serial_driver = platform.PlatformDriver {
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
};

fn serial_open(_: *kernel.fs.File, _: *kernel.fs.Inode) !void {
    kernel.logger.WARN("8250 file opened\n", .{});
}

fn serial_close(_: *kernel.fs.File) void {
}

fn serial_read(_: *kernel.fs.File, _: [*]u8, _: u32) !u32 {
    return 0;
}

fn serial_write(_: *kernel.fs.File, buf: [*]u8, size: u32) !u32 {
    const msg_slice: []const u8 = buf[0..size];
    kernel.serial.print(msg_slice);
    return size;
}

fn serial_probe(device: *platform.PlatformDevice) !void {
    try cdev.addCdev(&device.dev);
}

fn serial_remove(device: *platform.PlatformDevice) !void {
    _ = device;
    kernel.logger.WARN("serial cannot be initialized", .{});
}

pub fn init_serial() void {
    if (platform.PlatformDevice.alloc("8250")) |serial| {
        serial.register() catch {
            return ;
        };
        kernel.logger.WARN("Device registered for serial", .{});
        platform.platform_register_driver(&serial_driver.driver) catch |err| {
            kernel.logger.ERROR("Error registering platform driver: {!}", .{err});
            return ;
        };
        kernel.logger.WARN("Driver registered for serial", .{});
        return ;
    }
    kernel.logger.WARN("serial cannot be initialized", .{});
}

pub const Serial = struct {
    addr: u16 = 0x3F8, // COM1
    pub fn init() Serial {
        const serial = Serial{};
        io.outb(serial.addr + 1, 0x00);
        io.outb(serial.addr + 3, 0x80);
        io.outb(serial.addr, 0x01);
        io.outb(serial.addr + 1, 0x00);
        io.outb(serial.addr + 3, 0x03);
        io.outb(serial.addr + 2, 0xC7);
        io.outb(serial.addr + 1, 0x01);
        return serial;
    }

    pub fn putchar(self: *Serial, char: u8) void {
        while ((io.inb(self.addr + 5) & 0x20) == 0) {}
        io.outb(self.addr, char);
    }

    pub fn print(self: *Serial, message: []const u8) void {
        for (message) |char| {
            self.putchar(char);
        }
    }
};
