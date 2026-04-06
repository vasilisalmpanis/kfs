const krn = @import("kernel");
const arch = @import("arch");

const pdev = @import("../device.zig");
const pdrv = @import("../driver.zig");
const pbus = @import("../bus.zig");

const drv = @import("../../driver.zig");
const cdev = @import("../../cdev.zig");

var mouse_driver = pdrv.PlatformDriver {
    .driver = drv.Driver {
        .list = undefined,
        .name = "mice",
        .probe = undefined,
        .remove = undefined,
        .fops = &mouse_file_ops,
    },
    .probe = mouse_probe,
    .remove = mouse_remove,
};

pub export fn mouseHandler(_: ?*anyopaque) void{
    arch.io.outb(0x64, 0xA7);
    defer arch.io.outb(0x64, 0xA8);

    const packet = arch.io.inb(0x60);
    _ = packet;
}

fn mouse_probe(device: *pdev.PlatformDevice) !void {
    arch.cpu.disableInterrupts();
    waitPS2(true);
    arch.io.outb(0x64, 0xA8);
    waitPS2(true);
    arch.io.outb(0x64, 0x20);
    waitPS2(false);
    const status = arch.io.inb(0x60) | 2;
    waitPS2(true);
    arch.io.outb(0x64, 0x60);
    waitPS2(true);
    arch.io.outb(0x60, status);

    mouseWrite(0xF6); // set defaults
    _ = mouseRead();
    mouseWrite(0xF4); // enable data reporting
    _ = mouseRead();
    arch.cpu.enableInterrupts();
    krn.irq.registerHandler(12, mouseHandler, null);

    try cdev.addCdev(
        &device.dev,
        krn.fs.UMode.chardev(),
        "/dev/input"
    );
}

fn mouse_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
}

var mouse_file_ops = krn.fs.FileOps{
    .open = mouse_open,
    .close = mouse_close,
    .read = mouse_read,
    .write = mouse_write,
    .lseek = null,
    .readdir = null,
};

fn mouse_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {}

fn mouse_close(_: *krn.fs.File) void {}

fn mouse_read(file: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    _ = file;
    _ = buf;
    _ = size;
    return 0;
}

fn mouse_write(file: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = file;
    _ = buf;
    return size;
}

fn mouseRead() u8{
    waitPS2(false);
    return arch.io.inb(0x60);
}

fn mouseWrite(value: u8) void{
    waitPS2(true);
    arch.io.outb(0x64, 0xD4);
    waitPS2(true);
    arch.io.outb(0x60, value);
}

fn waitPS2(input: bool) void {
    while (true) {
        const status = arch.io.inb(0x64);
        if (input) {
            if (status & 0x2 == 0) break; // input buffer empty, safe to write
        } else {
            if (status & 0x1 != 0) break; // output buffer full, data available to read
        }
    }
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT mouse", .{});
    if (pdev.PlatformDevice.alloc("mice")) |mouse_dev| {
        mouse_dev.register() catch {
            return ;
        };
        krn.logger.WARN("Device registered for /dev/mouse", .{});
        pdrv.platform_register_driver(&mouse_driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver: {any}", .{err});
            return ;
        };
        krn.logger.WARN("Driver registered for /dev/mouse", .{});
        return ;
    }
    krn.logger.WARN("/dev/mouse cannot be initialized", .{});
}
