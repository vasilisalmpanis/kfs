const io = @import("arch").io;
const Shell = @import("shell.zig").Shell;
const printf = @import("debug").printf;
const scr = @import("./screen.zig");
const mm = @import("kernel").mm;

pub const ConsoleColors = enum(u32) {
    Black = 0x000000,
    Blue = 0x0000FF,
    Green = 0x00FF00,
    Cyan = 0x00FFFF,
    Red = 0xFF0000,
    Magenta = 0xFF00FF,
    Brown = 0xFFA500,
    LightGray = 0xD3D3D3,
    DarkGray = 0xa9a9a9,
    LightBlue = 0xADD8E6,
    LightGreen = 0xCFD8D9,
    LightCyan = 0xE0FFFF,
    LightRed = 0xFFCCCB,
    LightMagenta = 0xFF06B5,
    LightBrown = 0xC4A484,
    White = 0x00FFFFFF,
};                       


pub const TTY = struct {
    width: u32 = 80,
    height: u32 = 25,
    _x: u32 = 0,
    _y: u32 = 0,
    _bg_colour: u32 = @intFromEnum(ConsoleColors.Black),
    _fg_colour: u32 = @intFromEnum(ConsoleColors.White),
    _buffer : [*]u8,
    shell: *Shell,

    pub fn init(width: u32, height: u32) TTY {
        var tty = TTY{
            .width = width,
            .height = height,
            ._buffer = @ptrFromInt(mm.kmalloc(width * height * @sizeOf(u8))),
            .shell = Shell.init(),
        };
        @memset(tty._buffer[0..width * height], 0);
        tty.clear();
        return tty;
    }

    fn update_cursor(self: *TTY) void {
        scr.framebuffer.cursor(self._x, self._y, self._fg_colour);
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
                scr.framebuffer.putchar(c, col, row, self._bg_colour, self._fg_colour);
            }
        }
        self.update_cursor();
        scr.framebuffer.render();
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

    fn removeAtIndex(self: *TTY, index: usize) void {

        // Move the characters after the index to the left
        var i = index;
        while (i < self.height * self.width - 1) {
            self._buffer[i] = self._buffer[i + 1];
            i += 1;
        }

        self._buffer[self.width * self.height - 1] = 0;
    }

    pub fn remove(self: *TTY) void {
        if (self._x == 0 and self._y == 0)
            return;
        if (self._x > 0)
            self._x -= 1;
        self.removeAtIndex(self._y * self.width + self._x);
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
        // var res: [*]u8 = @ptrFromInt(mm.kmalloc(self.width * @sizeOf(u8)));
        var res: [240]u8 = .{0} ** (240);
        var i: u16 = 0;
        for (self._buffer[self._y * self.width..self._y * self.width + self._x]) |ch| {
            res[i] = ch;
            i += 1;
        }
        // mm.kfree(@intFromPtr(res));
        return res[0..i];
    }

    fn printChar(self: *TTY, c: u8) void {
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
            self.print("    ", false);
        } else {
            self.printVga(c);
        }
    }

    pub fn print(self: *TTY, msg: [] const u8, stdin: bool) void {
        var str: [*]u8 = @ptrFromInt(mm.kmalloc(self.width * @sizeOf(u8)));
        // var str: [240]u8 = .{0} ** 240;
        @memset(str[0..self.width], 0);
        var len: u8 = 0;
        var buf: [*]u8 = @ptrFromInt(mm.kmalloc(self.width * @sizeOf(u8)));
        // var buf: [240]u8 = .{0} ** 240;
        @memset(buf[0..self.width], 0);
        const start = self._y * self.width + self._x;
        const max_end: u32 = (self._y + 1) * self.width;
        var end: u32 = start;
        while (self._buffer[end] != 0 and end < max_end)
            end += 1;
        @memcpy(buf[0..(end - start)], self._buffer[start..end]);
        for (msg) |c| {
            if (c == '\n' and stdin) {
                for (self.getCurrentLine()) |cc| {
                    str[len] = cc;
                    len += 1;
                }
            }
            self.printChar(c);
        }
        const x = self._x;
        const y = self._y;
        var i: u16 = 0;
        while (i < end - start) : (i += 1)
            self.printVga(buf[i]);
        self._x = x;
        self._y = y;
        self.render();
        if (stdin and str[0] != 0)
            self.shell.handleInput(str[0..len]);
        mm.kfree(@intFromPtr(str));
        mm.kfree(@intFromPtr(buf));
    }

    pub fn setColor(self: *TTY, fg: u32) void {
        self._fg_colour = fg;
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
