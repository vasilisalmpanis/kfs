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

const krn = @import("kernel");

pub fn init() void {
    krn.sysfs.init_sys();
    _ = krn.mkdir("/sys", 0) catch {
        @panic("unable to create /sys directory");
    };
    _ = krn.mount("", "/sys", "sysfs", 0, null) catch |err| {
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
}
