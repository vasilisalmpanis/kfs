pub const bus = @import("./bus.zig");
pub const driver = @import("./driver.zig");
pub const device = @import("./device.zig");
pub const serial = @import("./serial.zig");
pub const nulldev = @import("./null.zig");
pub const tty = @import("./tty.zig");
pub const fb = @import("fb.zig");

pub const PlatformDevice = device.PlatformDevice;
pub const PlatformDriver = driver.PlatformDriver;

pub const Serial = serial.Serial;
pub const TTY = tty.TTY;
