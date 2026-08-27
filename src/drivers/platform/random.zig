const krn = @import("kernel");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

fn mkDriver(comptime name: []const u8, fops: *krn.fs.FileOps) pdrv.PlatformDriver {
    return .{
        .driver = drv.Driver {
            .list = undefined,
            .name = name,
            .probe = undefined,
            .remove = undefined,
            .fops = fops,
        },
        .probe = dev_probe,
        .remove = dev_remove,
    };
}

var random_driver = mkDriver("random", &random_file_ops);
var urandom_driver = mkDriver("urandom", &random_file_ops);
var zero_driver = mkDriver("zero", &zero_file_ops);

fn dev_probe(device: *pdev.PlatformDevice) !void {
    try cdev.addCdev(&device.dev, krn.fs.UMode.chardev(), null);
}

fn dev_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
}

var random_file_ops = krn.fs.FileOps{
    .open = dev_open,
    .close = dev_close,
    .read = random_read,
    .write = random_write,
    .lseek = null,
    .readdir = null,
};

var zero_file_ops = krn.fs.FileOps{
    .open = dev_open,
    .close = dev_close,
    .read = zero_read,
    .write = sink_write,
    .lseek = null,
    .readdir = null,
};

fn dev_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {}

fn dev_close(_: *krn.fs.File) void {}

fn random_read(_: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    krn.random.fill(buf[0..size]);
    return size;
}

fn random_write(_: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    krn.random.mix(buf[0..size]);
    return size;
}

fn zero_read(_: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    @memset(buf[0..size], 0);
    return size;
}

fn sink_write(_: *krn.fs.File, _: [*]const u8, size: usize) !usize {
    return size;
}

fn initDev(name: []const u8, driver: *pdrv.PlatformDriver) void {
    if (pdev.PlatformDevice.alloc(name)) |device| {
        device.register() catch return;
        pdrv.platform_register_driver(&driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver {s}: {any}", .{name, err});
            return;
        };
        return;
    }
    krn.logger.WARN("/dev/{s} cannot be initialized", .{name});
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT random", .{});
    krn.random.init();
    initDev("random", &random_driver);
    initDev("urandom", &urandom_driver);
    initDev("zero", &zero_driver);
}
