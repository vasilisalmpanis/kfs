const krn = @import("kernel");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");
const pbus = @import("./bus.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

var null_driver = pdrv.PlatformDriver {
    .driver = drv.Driver {
        .list = undefined,
        .name = "null",
        .probe = undefined,
        .remove = undefined,
        .fops = &null_file_ops,
    },
    .probe = null_probe,
    .remove = null_remove,
};

fn null_probe(device: *pdev.PlatformDevice) !void {
    try cdev.addCdev(&device.dev, krn.fs.UMode.chardev());
}

fn null_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
}

var null_file_ops = krn.fs.FileOps{
    .open = null_open,
    .close = null_close,
    .read = null_read,
    .write = null_write,
    .lseek = null,
    .readdir = null,
};

fn null_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {}

fn null_close(_: *krn.fs.File) void {}

fn null_read(file: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    _ = file;
    _ = buf;
    _ = size;
    return 0;
}

fn null_write(file: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = file;
    _ = buf;
    return size;
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT null", .{});
    if (pdev.PlatformDevice.alloc("null")) |null_dev| {
        null_dev.register() catch {
            return ;
        };
        krn.logger.WARN("Device registered for /dev/null", .{});
        pdrv.platform_register_driver(&null_driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver: {any}", .{err});
            return ;
        };
        krn.logger.WARN("Driver registered for /dev/null", .{});
        return ;
    }
    krn.logger.WARN("/dev/null cannot be initialized", .{});
}
