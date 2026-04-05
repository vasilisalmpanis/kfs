const krn = @import("kernel");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");
const pbus = @import("./bus.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

var fb_driver = pdrv.PlatformDriver {
    .driver = drv.Driver {
        .list = undefined,
        .name = "fb",
        .probe = undefined,
        .remove = undefined,
        .fops = &fb_file_ops,
    },
    .probe = fb_probe,
    .remove = fb_remove,
};

fn fb_probe(device: *pdev.PlatformDevice) !void {
    try cdev.addCdev(&device.dev, krn.fs.UMode.chardev());
}

fn fb_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
}

var fb_file_ops = krn.fs.FileOps{
    .open = fb_open,
    .close = fb_close,
    .read = fb_read,
    .write = fb_write,
    .lseek = null,
    .readdir = null,
};

fn fb_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {}

fn fb_close(_: *krn.fs.File) void {}

fn fb_read(file: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    _ = file;
    _ = buf;
    _ = size;
    return 0;
}

fn fb_write(file: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = file;
    _ = buf;
    return size;
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT fb", .{});
    if (pdev.PlatformDevice.alloc("fb0")) |fb_dev| {
        fb_dev.register() catch {
            return ;
        };
        krn.logger.WARN("Device registered for /dev/fb0", .{});
        pdrv.platform_register_driver(&fb_driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver: {any}", .{err});
            return ;
        };
        krn.logger.WARN("Driver registered for /dev/fb", .{});
        return ;
    }
    krn.logger.WARN("/dev/fb cannot be initialized", .{});
}
