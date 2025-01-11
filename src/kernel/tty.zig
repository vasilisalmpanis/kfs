const io = @import("arch").io;
const Shell = @import("shell.zig").Shell;
const printf = @import("printf.zig").printf;

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

const ft = 
\\       444444444     222222222222222    
\\      4::::::::4    2:::::::::::::::22  
\\     4:::::::::4    2::::::222222:::::2 
\\    4::::44::::4    2222222     2:::::2 
\\   4::::4 4::::4                2:::::2 
\\  4::::4  4::::4                2:::::2 
\\ 4::::4   4::::4             2222::::2  
\\4::::444444::::444      22222::::::22   
\\4::::::::::::::::4    22::::::::222     
\\4444444444:::::444   2:::::22222        
\\          4::::4    2:::::2             
\\          4::::4    2:::::2             
\\          4::::4    2:::::2       222222
\\        44::::::44  2::::::2222222:::::2
\\        4::::::::4  2::::::::::::::::::2
\\        4444444444  22222222222222222222
;                        

pub fn vga_entry_color(fg: ConsoleColors, bg: ConsoleColors) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

pub const TTY = struct {
    width: u16 = 80,
    height: u16 = 25,
    _vga: [*]u16 = @ptrFromInt(0xB8000),
    _x: u16 = 0,
    _y: u16 = 0,
    _terminal_color: u8 = 0,
    _buffer : [80 * 25] u16,
    shell: *Shell,

    pub fn init(width: u16, height: u16) TTY {
        var tty = TTY{
            .width = width,
            .height = height,
            ._terminal_color = vga_entry_color(ConsoleColors.White, ConsoleColors.Black),
            ._buffer = .{0} ** (80 * 25),
            .shell = Shell.init(),
        };
        tty.clear();
        return tty;
    }

    fn update_cursor(self: *TTY) void {
        const pos : u16 = self._y * self.width + self._x;

        io.outb(0x3D4, 0x0F);
        io.outb(0x3D5, @intCast(pos & 0xFF));
        io.outb(0x3D4, 0x0E);
        io.outb(0x3D5, @intCast((pos >> 8) & 0xFF));
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
        @memcpy(self._vga[0..2000], self._buffer[0..2000]);
        self.update_cursor();

    }

    pub fn print42(self: *TTY) void {
        const offset_x: u16 = 20;
        const offset_y: u16 = 5;
        @memset(
            self._vga[0..80 * 25],
            self.vga_entry(
                ' ',
                vga_entry_color(ConsoleColors.Cyan, ConsoleColors.DarkGray)
            )
        );
        var x: u16 = offset_x;
        var y: u16 = offset_y;
        for (ft) |c| {
            if (c == '\n') {
                y += 1;
                x = offset_x;
                continue;
            }
            self._vga[y * 80 + x] = self.vga_entry(
                c,
                vga_entry_color(ConsoleColors.Cyan, ConsoleColors.DarkGray)
            );
            x += 1;
        }
    }

    fn _scroll(self: *TTY) void {
        var i: u16 = 1;
        while (i < self.height) : (i += 1) {
            const p: u16 = i * self.width;
            @memcpy(
                self._buffer[p - self.width..p],
                self._buffer[p..p + self.width]
            );
        }
        const p: u16 = self.height * self.width;
        @memset(
            self._buffer[p - self.width..p],
            self.vga_entry(0, self._terminal_color)
        );
        self._y = self.height - 1;
        self.render();
    }

    fn removeAtIndex(self: *TTY, comptime T: type, buffer: []T, index: usize) void {

        // Move the characters after the index to the left
        var i = index;
        while (i < 80 * 25 - 1) {
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
        self.removeAtIndex(u16, &self._buffer, self._y * self.width + self._x);
        self.render();
    }

    pub fn clear(self: *TTY) void {
        @memset(
            self._buffer[0..self.height * self.width],
            self.vga_entry(0, self._terminal_color)
        );
        self._x = 0;
        self._y = 0;
        self.render();
    }

    fn printVga(self: *TTY, vga_item: u16) void {
        self._buffer[self._y * self.width + self._x] = vga_item;
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
        var res: [80]u8 = .{0} ** 80;
        var i: u16 = 0;
        for (self._buffer[self._y * self.width..self._y * self.width + self._x]) |vga| {
            const c: u8 = self.getCharacterFromVgaEntry(vga);
            res[i] = c;
            i += 1;
        }
        return res[0..i];
    }

    fn printChar(self: *TTY, c: u8, color: ?u8) void {
        if (c == '\n') {
             @memset(
                self._buffer[self.width * self._y + self._x .. self.width * self._y + self.width],
                self.vga_entry(0, self._terminal_color)
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
            self.printVga(self.vga_entry(
                c,
                color orelse self._terminal_color)
            );
        }
    }

    pub fn print(self: *TTY, msg: [] const u8, color: ?u8, stdin: bool) void {
        var str: [80]u8 = .{0} ** 80;
        var len: u8 = 0;
        var buf = [_]u16{0} ** 80;
        const start = self._y * self.width + self._x;
        const max_end: u16 = (self._y + 1) * self.width;
        var end: u16 = start;
        while (self.getCharacterFromVgaEntry(self._buffer[end]) != 0 and end < max_end)
            end += 1;
        @memcpy(buf[0..(end - start)], self._buffer[start..end]);
        for (msg) |c| {
            if (c == '\n' and stdin) {
                for (self.getCurrentLine()) |cc| {
                    str[len] = cc;
                    len += 1;
                }
            }
            self.printChar(c, color);
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
