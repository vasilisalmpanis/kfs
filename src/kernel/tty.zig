
pub const TTY = struct {
    width: u16,
    height: u16,
    _vga: [*]u16 = @ptrFromInt(0xB8000),
    _x: u16 = 0,
    _y: u16 = 0,

    pub fn init(width: u16, height: u16) TTY {
        return TTY{
            .width = width,
            .height = height,
        };
    }

    fn _scroll() void {}

    pub fn print(self: TTY, msg: [*:0] const u8, len: usize) void {
        var idx: usize = 0;
        while (idx < len ) : (idx += 1)
            self._vga[idx] = (0x0f << 8) | @as(u16, msg[idx]);
    }

    pub fn setColor() void {}

};
