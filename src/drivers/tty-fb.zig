const io = @import("arch").io;
const Shell = @import("shell.zig").Shell;
const printf = @import("debug").printf;
const scr = @import("./screen.zig");
const mm = @import("kernel").mm;

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
    width: u32 = 80,
    height: u32 = 25,
    _x: u32 = 0,
    _y: u32 = 0,
    _terminal_color: u8 = 0,
    _buffer : [*]u8,
    shell: *Shell,

    pub fn init(width: u32, height: u32) TTY {
        var tty = TTY{
            .width = width,
            .height = height,
            ._terminal_color = vga_entry_color(ConsoleColors.White, ConsoleColors.Black),
            ._buffer = @ptrFromInt(mm.kmalloc(width * height * @sizeOf(u8))),
            .shell = Shell.init(),
        };
        @memset(tty._buffer[0..width * height], 0);
        tty.clear();
        return tty;
    }

    fn update_cursor(self: *TTY) void {
        scr.framebuffer.cursor(self._x, self._y);
    }

    pub fn move(self: *TTY, direction : u8) void {
        if (direction == 0) {
            if (self._x > 0)
                self._x -= 1;
        } else {
            if (self._x < self.width - 1)
                self._x += 1;
        }
        self.render();
    }

    pub fn render(self: *TTY) void {
        for (0..self.height) |row| {
            for (0..self.width) |col| {
                const c = self._buffer[row * self.width + col];
                scr.framebuffer.putchar(c, col, row);
            }
        }
        self.update_cursor();
    }

    fn _scroll(self: *TTY) void {
        var i: u32 = 1;
        while (i < self.height) : (i += 1) {
            const p: u32 = i * self.width;
            @memcpy(
                self._buffer[p - self.width..p],
                self._buffer[p..p + self.width]
            );
        }
        const p: u32 = self.height * self.width;
        @memset(
            self._buffer[p - self.width..p],
            0
        );
        self._y = self.height - 1;
        self.render();
    }

    fn removeAtIndex(self: *TTY, comptime T: type, buffer: [*]T, index: usize) void {

        // Move the characters after the index to the left
        var i = index;
        while (i < 80 * 25 - 1) {
            buffer[i] = buffer[i + 1];
            i += 1;
        }

        buffer[80 * 25 - 1] = 0;
        _ = self;
    }

    pub fn remove(self: *TTY) void {
        if (self._x == 0 and self._y == 0)
            return;
        if (self._x > 0)
            self._x -= 1;
        self.removeAtIndex(u8, self._buffer, self._y * self.width + self._x);
        self.render();
    }

    pub fn clear(self: *TTY) void {
        @memset(
            self._buffer[0..self.height * self.width],
            0
        );
        self._x = 0;
        self._y = 0;
        self.render();
    }

    fn printVga(self: *TTY, ch: u8) void {
        self._buffer[self._y * self.width + self._x] = ch;
        self._x += 1;
        if (self._x >= self.width) {
            self._x = 0;
            self._y += 1;
        }
        if (self._y >= self.height)
            self._scroll();
    }

    fn getCurrentLine(self: *TTY) []u8 {
        if (self._x == 0)
            return "";
        var res: [*]u8 = @ptrFromInt(mm.kmalloc(self.width * @sizeOf(u8)));
        var i: u16 = 0;
        for (self._buffer[self._y * self.width..self._y * self.width + self._x]) |ch| {
            res[i] = ch;
            i += 1;
        }
        return res[0..i];
    }

    fn printChar(self: *TTY, c: u8, color: ?u8) void {
        _ = color;
        if (c == '\n') {
             @memset(
                self._buffer[self.width * self._y + self._x .. self.width * self._y + self.width],
                0
            );
            self._y += 1;
            self._x = 0;
            if (self._y >= self.height)
                self._scroll();
        } else if (c == 8) {
            self.remove();
        } else if (c == '\t') {
            self.print("    ", null, false);
        } else {
            self.printVga(c);
        }
    }

    pub fn print(self: *TTY, msg: [] const u8, color: ?u8, stdin: bool) void {
        for (msg) |c| {
            self.printChar(c, color);
        }
        self.render();
        _ = stdin;

        // var str: [*]u8 = @ptrFromInt(mm.kmalloc(self.width * @sizeOf(u8)));
        // var len: u8 = 0;
        // var buf: [*]u8 = @ptrFromInt(mm.kmalloc(self.width * @sizeOf(u8)));
        // const start = self._y * self.width + self._x;
        // const max_end: u32 = (self._y + 1) * self.width;
        // var end: u32 = start;
        // while (self._buffer[end] != 0 and end < max_end)
        //     end += 1;
        // @memcpy(buf[0..(end - start)], self._buffer[start..end]);
        // for (msg) |c| {
        //     if (c == '\n' and stdin) {
        //         for (self.getCurrentLine()) |cc| {
        //             str[len] = cc;
        //             len += 1;
        //         }
        //     }
        //     self.printChar(c, color);
        // }
        // const x = self._x;
        // const y = self._y;
        // var i: u16 = 0;
        // while (i < end - start) : (i += 1)
        //     self.printVga(buf[i]);
        // self._x = x;
        // self._y = y;
        // self.render();
        // if (stdin and str[0] != 0)
        //     self.shell.handleInput(str[0..len]);
    }

    pub fn setColor(self: *TTY, new_color: u8) void {
        self._terminal_color = new_color;
    }

    pub fn vga_entry(self: *TTY, uc: u8, new_color: u8) u16 {
        _ = self;
        const c: u16 = new_color;

        return uc | (c << 8);
    }

    fn getCharacterFromVgaEntry(self: *TTY, entry: u16) u8 {
        _ = self;
        return @intCast(entry & 0xFF);
    }
};
