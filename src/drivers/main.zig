pub const Keyboard = @import("kbd.zig").Keyboard;
pub const screen = @import("./screen.zig");
pub const shell = @import("./shell.zig");
pub const framebuffer = @import("./framebuffer.zig");
pub const keyboard = @import("./kbd.zig");
pub const pit = @import("./pit.zig");

pub const storage = @import("./storage/main.zig");
// pub const pci = @import("./pci.zig");
pub const cmos = @import("./cmos.zig");

pub const bus = @import("bus.zig");
pub const device = @import("./device.zig");
pub const driver = @import("./driver.zig");
pub const cdev = @import("./cdev.zig");
pub const bdev = @import("./bdev.zig");
const krn = @import("kernel");

pub const platform = @import("./platform/main.zig");
pub const Serial = platform.Serial;

pub const pci = @import("./pci/main.zig");

pub var devfs_path: krn.fs.path.Path = undefined;

pub fn init() void {
    _ = krn.mkdir("/sys", 0o444) catch {
        @panic("unable to create /sys directory");
    };
    _ = krn.do_mount("sys", "/sys", "sysfs", 0, null) catch |err| {
        krn.logger.ERROR("{any}", .{err});
        @panic("unable to mount sysfs");
    };
    _ = krn.mkdir("/sys/bus", 0o444) catch {
        @panic("unable to create /sys/bus directory");
    };
    const path = krn.fs.path.resolve("/sys/bus") catch {
        @panic("unable to init devices");
    };
    bus.sysfs_bus_dentry = path.dentry;

    _ = krn.mkdir("/dev", 0o444) catch {
        @panic("unable to create /dev directory");
    };
    _ = krn.do_mount("dev", "/dev", "devfs", 0, null) catch |err| {
        krn.logger.ERROR("{any}", .{err});
        @panic("unable to mount devfs");
    };
    devfs_path = krn.fs.path.resolve("/dev") catch {
        @panic("unable to init devfs");
    };

    cdev.init();
    bdev.init();

    platform.bus.init();
    pci.bus.init();
    storage.bus.init();

    platform.serial.init();
    platform.tty.init();
    pci.ide.init();
    storage.ata.init();
}
