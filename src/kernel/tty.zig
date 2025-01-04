
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

    fn _scroll(self: *TTY) void {
        self._y = 0;
    }

    fn printChar(self: *TTY, c: u8) void {
        if (c == '\n') {
            self._y += 1;
            self._x = 0;
            if (self._y >= self.height) {
                self._scroll();
            }
            return ;
        }
        self._vga[self._y * self.width + self._x] = (0x0f << 8) | @as(u16, c);
        self._x += 1;
        if (self._x >= self.width) {
            self._x = 0;
            self._y += 1;
        }
        if (self._y >= self.height) {
            self._scroll();
        }
    }

    pub fn print(self: *TTY, msg: [*:0] const u8) void {
        var idx: usize = 0;
        while (msg[idx] != 0) : (idx += 1)
            self.printChar(msg[idx]);
    }

    pub fn setColor() void {}

};
