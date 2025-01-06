const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;

pub const ConsoleColors = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

pub fn vga_entry_color(fg: ConsoleColors, bg: ConsoleColors) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

pub const TTY = struct {
    width: u16,
    height: u16,
    _vga: [*]u16 = @ptrFromInt(0xB8000),
    _x: u16 = 0,
    _y: u16 = 0,
    _terminal_color: u8 = 0,

    pub fn init(width: u16, height: u16) TTY {
        var tty = TTY{
            .width = width,
            .height = height,
            ._terminal_color = vga_entry_color(ConsoleColors.White, ConsoleColors.Black),
        };
        tty.clear();
        return tty;
    }

    fn _scroll(self: *TTY) void {
        var i: u16 = 1;
        while (i < self.height) : (i += 1) {
            const p: u16 = i * self.width;
            @memcpy(
                self._vga[p - self.width..p],
                self._vga[p..p + self.width]
            );
        }
        const p: u16 = i * self.width;
        @memset(
            self._vga[p - self.width..p],
            self.vga_entry(0, self._terminal_color)
        );
        self._y = self.height - 1;
    }

    fn removeAtIndex(self: *TTY, comptime T: type, buffer: [*]T, index: usize) void {

        // Move the characters after the index to the left
        var i = index;
        while (i < 80 * 25) {
            buffer[i] = buffer[i + 1];
            i += 1;
        }

        buffer[80 * 25 - 1] = self.vga_entry(0, self._terminal_color);
    }

    pub fn remove(self: *TTY) void {
        if (self._x == 0 and self._y == 0)
            return;
        if (self._x > 0)
            self._x -= 1;
        self.removeAtIndex(u16, self._vga, self._y * self.width + self._x);
    }

    pub fn clear(self: *TTY) void {
        @memset(
            self._vga[0..self.height * self.width],
            self.vga_entry(0, self._terminal_color)
        );
        self._x = 0;
        self._y = 0;
    }

    fn printVga(self: *TTY, vga_item: u16) void {
        self._vga[self._y * self.width + self._x] = vga_item;
        self._x += 1;
        if (self._x >= self.width) {
            self._x = 0;
            self._y += 1;
        }
        if (self._y >= self.height)
            self._scroll();
    }

    fn printChar(self: *TTY, c: u8, color: ?u8) void {
        if (c == '\n') {
            self._y += 1;
            self._x = 0;
            if (self._y >= self.height)
                self._scroll();
            return;
        }
        self.printVga(self.vga_entry(
            c,
            color orelse self._terminal_color)
        );
    }

    pub fn print(self: *TTY, msg: [] const u8, color: ?u8) void {
        var buf = [_]u16{0} ** 80;
        const empty = self.vga_entry(0, self._terminal_color);
        const start = self._y * self.width + self._x;
        const max_end: u16 = (self._y + 1) * self.width;
        var end: u16 = start;
        while (self._vga[end] != empty and end < max_end)
            end += 1;
        @memcpy(buf[0..(end - start)], self._vga[start..end]);
        for (msg) |c|
            self.printChar(c, color);
        var i: u16 = 0;
        while (i < end - start) : (i += 1)
            self.printVga(buf[i]);
    }

    pub fn setColor(self: *TTY, new_color: u8) void {
        self._terminal_color = new_color;
    }

    pub fn vga_entry(self: *TTY, uc: u8, new_color: u8) u16 {
        _ = self;
        const c: u16 = new_color;

        return uc | (c << 8);
    }
};

pub var current_tty: ?*TTY = null;
pub const writer = Writer(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!usize {
    const color: u8 = vga_entry_color(ConsoleColors.White, ConsoleColors.Black);
    // Print the string passed to the callback
    if (current_tty) |t|
        t.print(string, color);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    // current_tty.?.print("called\n", current_tty.?._terminal_color);
    fmt.format(writer, format, args) catch unreachable;
}
