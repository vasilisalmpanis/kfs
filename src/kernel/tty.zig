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
        return TTY{
            .width = width,
            .height = height,
            ._terminal_color = vga_entry_color(ConsoleColors.White, ConsoleColors.Black),
        };
    }

    fn _scroll(self: *TTY) void {
        var i: u16 = 1;
        while (i < self.height) : (i += 1) {
            var j: u16 = 0;
            while (j < self.width) : (j += 1)
                self._vga[(i - 1) * self.width + j] = self._vga[i * self.width + j];
        }
        var j: u16 = 0;
        while (j < self.width) : (j += 1)
            self._vga[(self.height - 1) * self.width + j] = 0;
        self._y = self.height - 1;
    }

    fn printChar(self: *TTY, c: u8, color: ?u8) void {
        const final_color: u8 = color orelse self._terminal_color;
        if (c == '\n') {
            self._y += 1;
            self._x = 0;
            if (self._y >= self.height)
                self._scroll();
            return;
        }
        self._vga[self._y * self.width + self._x] = self.vga_entry(c, final_color);
        self._x += 1;
        if (self._x >= self.width) {
            self._x = 0;
            self._y += 1;
        }
        if (self._y >= self.height)
            self._scroll();
    }

    pub fn print(self: *TTY, msg: []const u8, color: ?u8) void {
        for (msg) |c| {
            self.printChar(c, color);
        }
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
    if (current_tty == null) {
        return string.len;
    }
    current_tty.?.print(string, color);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    current_tty.?.print("called\n", current_tty.?._terminal_color);
    fmt.format(writer, format, args) catch unreachable;
}
