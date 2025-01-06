const tty = @import("tty.zig");

pub const Screen = struct {
    tty : [10] tty.TTY,
    pub fn init() Screen {
        return .{
            .tty = .{tty.TTY.init(80,25)} ** 10,
        };
    }
};
