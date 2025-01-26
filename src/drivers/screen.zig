const tty = @import("tty.zig");

pub var current_tty: ?*tty.TTY = null;

pub const Screen = struct {
    tty : [10] tty.TTY,
    pub fn init() *Screen {
        var scr = Screen{
            .tty = .{tty.TTY.init(80,25)} ** 10,
        };
        current_tty = &scr.tty[0];
        return &scr;
    }

    pub fn switch_tty(self: *Screen, num: u8) void {
        current_tty = &self.tty[num];
        current_tty.?.render();
    }
};
