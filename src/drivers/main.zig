pub const Keyboard = @import("kbd.zig").Keyboard;
pub const Serial = @import("serial.zig").Serial;
pub const screen = @import("./screen.zig");
pub const tty = @import("./tty-fb.zig");
pub const shell = @import("./shell.zig");
pub const framebuffer = @import("./framebuffer.zig");
pub const keyboard = @import("./kbd.zig");
pub const pit = @import("./pit.zig");

pub const ata = @import("./block/ata/ata.zig");
pub const test_init = @import("./block/ata/test.zig");
pub const pci = @import("./pci.zig");

// If no other function from a file is used
// the zig compiler drops the entire module as
// dead code. We need to ref the module at some
// point that will be examined by the compiler.
// It is okay to do that in each subsystem.
// Later when other functions of the module will be
// used the entry can be removed.
comptime {
    _ = pci.init;
    _ = ata.ata_init;
    _ = test_init.test_init;
}
