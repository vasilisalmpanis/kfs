pub const Keyboard = @import("kbd.zig").Keyboard;
pub const Serial = @import("serial.zig").Serial;
pub const screen = @import("./screen.zig");
pub const tty = @import("./tty-fb.zig");
pub const shell = @import("./shell.zig");
pub const framebuffer = @import("./framebuffer.zig");
pub const keyboard = @import("./kbd.zig");
pub const pit = @import("./pit.zig");

pub const ata = @import("./block/ata/ata.zig");
pub const pci = @import("./pci.zig");
