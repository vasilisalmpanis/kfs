pub const Keyboard = @import("kbd.zig").Keyboard;
pub const Serial = @import("serial.zig").Serial;
pub const init_serial = @import("serial.zig").init_serial;
pub const init_platform = @import("./buses/platform.zig").init_platform;
pub const screen = @import("./screen.zig");
pub const tty = @import("./tty-fb.zig");
pub const shell = @import("./shell.zig");
pub const framebuffer = @import("./framebuffer.zig");
pub const keyboard = @import("./kbd.zig");
pub const pit = @import("./pit.zig");

pub const ata = @import("./block/ata/ata.zig");
pub const pci = @import("./pci.zig");
pub const cmos = @import("./cmos.zig");

pub const bus = @import("bus.zig");
pub const device = @import("./device.zig");
pub const cdev = @import("./cdev.zig");
pub const bdev = @import("./bdev.zig");
const krn = @import("kernel");


pub var devfs_path: krn.fs.path.Path = undefined;

pub fn init() void {
    // Init /sys 
    krn.sysfs.init_sys();
    _ = krn.mkdir("/sys", 0) catch {
        @panic("unable to create /sys directory");
    };
    _ = krn.mount("sys", "/sys", "sysfs", 0, null) catch |err| {
        krn.logger.ERROR("{!}", .{err});
        @panic("unable to mount sysfs");
    };
    _ = krn.mkdir("/sys/bus", 0) catch {
        @panic("unable to create /sys/bus directory");
    };
    const path = krn.fs.path.resolve("/sys/bus") catch {
        @panic("unable to init devices");
    };
    bus.sysfs_bus_dentry = path.dentry;

    // Init /dev
    krn.devfs.init_dev();
    _ = krn.mkdir("/dev", 0) catch {
        @panic("unable to create /dev directory");
    };
    _ = krn.mount("dev", "/dev", "devfs", 0, null) catch |err| {
        krn.logger.ERROR("{!}", .{err});
        @panic("unable to mount devfs");
    };
    devfs_path = krn.fs.path.resolve("/dev") catch {
        @panic("unable to init devfs");
    };

    cdev.init();
}
