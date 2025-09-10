const io = @import("arch").io;
const Shell = @import("shell.zig").Shell;
const printf = @import("debug").printf;
const scr = @import("./screen.zig");
const mm = @import("kernel").mm;
const KeyEvent = @import("./kbd.zig").KeyEvent;
const CtrlType = @import("./kbd.zig").CtrlType;
const krn = @import("kernel");

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

pub const DirtyRect = struct {
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,
    
    pub fn init(x1: u32, y1: u32, x2: u32, y2: u32) DirtyRect {
        return DirtyRect{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2,
        };
    }
    
    pub fn fullScreen(width: u32, height: u32) DirtyRect {
        return DirtyRect{
            .x1 = 0,
            .y1 = 0,
            .x2 = width - 1,
            .y2 = height - 1,
        };
    }
    
    pub fn singleChar(x: u32, y: u32) DirtyRect {
        return DirtyRect{
            .x1 = x,
            .y1 = y,
            .x2 = x,
            .y2 = y,
        };
    }
    
    pub fn line(y: u32, x1: u32, x2: u32) DirtyRect {
        return DirtyRect{
            .x1 = x1,
            .y1 = y,
            .x2 = x2,
            .y2 = y,
        };
    }
    
    pub fn merge(self: DirtyRect, other: DirtyRect) DirtyRect {
        return DirtyRect{
            .x1 = @min(self.x1, other.x1),
            .y1 = @min(self.y1, other.y1),
            .x2 = @max(self.x2, other.x2),
            .y2 = @max(self.y2, other.y2),
        };
    }
    
    pub fn isEmpty(self: DirtyRect) bool {
        return self.x1 > self.x2 or self.y1 > self.y2;
    }
};

pub const TTY = struct {
    width: u32 = 80,
    height: u32 = 25,
    _x: u32 = 0,
    _y: u32 = 0,
    _bg_colour: u32 = @intFromEnum(ConsoleColors.Black),
    _fg_colour: u32 = @intFromEnum(ConsoleColors.White),
    _buffer : [*]u8,
    _prev_buffer : [*]u8,
    _line: [*]u8,
    _input_len: u32 = 0,
    _prev_x: u32 = 0,
    _prev_y: u32 = 0,
    _dirty_rect: DirtyRect = DirtyRect.init(0, 0, 0, 0),
    _has_dirty_rect: bool = false,
    shell: Shell,

    pub fn init(width: u32, height: u32) TTY {
        const buffer: [*]u8 = if (mm.kmallocArray(u8, width * height)) |buf| buf else @panic("buffer");
        const prev_buffer: [*]u8 = if (mm.kmallocArray(u8, width * height)) |buf| buf else @panic("prev_buffer");
        const line: [*]u8 = if (mm.kmallocArray(u8, width)) |_line| _line else @panic("line");
            var tty = TTY{
                .width = width,
                .height = height,
                ._buffer = buffer,
                ._prev_buffer = prev_buffer,
                ._line = line,
                .shell = Shell.init(),
            };
            @memset(tty._buffer[0..width * height], 0);
            @memset(tty._prev_buffer[0..width * height], 0);
            tty.clear();
            return tty;
    }

    fn renderCursor(self: *TTY) void {
        scr.framebuffer.cursor(self._x, self._y, self._fg_colour);
    }

    fn saveCursor(self: *TTY) void {
        self._prev_x = self._x;
        self._prev_y = self._y;
    }

    fn move(self: *TTY, direction : u8) void {
        self.saveCursor();
        if (direction == 0) {
            if (self._x > 0)
                self._x -= 1;
        } else {
            if (
                self._x < self.width - 1
                and self._buffer[self._y * self.width + self._x] != 0
            )
                self._x += 1;
        }
        self.render();
    }

    fn cursorUpdated(self: *TTY) bool {
        return (self._x != self._prev_x or self._y != self._prev_y);
    }

    pub fn reRenderAll(self: *TTY) void {
        scr.framebuffer.clear(self._bg_colour);
        @memset(
            self._prev_buffer[0..self.height * self.width],
            0
        );
        self.markDirty(DirtyRect.fullScreen(
            self.width,
            self.height
        ));
        self.render();
    }

    pub fn render(self: *TTY) void {
        if (!self._has_dirty_rect and !self.cursorUpdated())
            return ;
        if (self._has_dirty_rect) {
            const x1 = self._dirty_rect.x1;
            const y1 = self._dirty_rect.y1;
            const x2 = @min(self._dirty_rect.x2, self.width - 1);
            const y2 = @min(self._dirty_rect.y2, self.height - 1);

            for (y1..(y2 + 1)) |row| {
                for (x1..(x2 + 1)) |col| {
                    const c = self._buffer[row * self.width + col];
                    if (c != self._prev_buffer[row * self.width + col]) {
                        scr.framebuffer.putchar(
                            c,
                            col, row,
                            self._bg_colour,
                            self._fg_colour
                        );
                        self._prev_buffer[row * self.width + col] = c;
                    }
                }
            }
        }
        const c = self._buffer[self._prev_y * self.width + self._prev_x];
        scr.framebuffer.putchar(
            c,
            self._prev_x, self._prev_y,
            self._bg_colour,
            self._fg_colour
        );
        self.renderCursor();
        scr.framebuffer.render();
        self._has_dirty_rect = false;
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
        @memset(
            self._prev_buffer[p - self.width..p],
            1
        );
        self._y = self.height - 1;
        self.saveCursor();
        self.markDirty(DirtyRect.fullScreen(self.width, self.height));
    }

    fn clear(self: *TTY) void {
        @memset(
            self._buffer[0..self.height * self.width],
            0
        );
        self.saveCursor();
        self._x = 0;
        self._y = 0;
        self.markDirty(DirtyRect.fullScreen(
            self.width,
            self.height
        ));
        self.render();
    }

    fn markDirty(self: *TTY, rect: DirtyRect) void {
        if (self._has_dirty_rect) {
            self._dirty_rect = self._dirty_rect.merge(rect);
        } else {
            self._dirty_rect = rect;
            self._has_dirty_rect = true;
        }
    }
    
    fn markCellDirty(self: *TTY, x: u32, y: u32) void {
        self.markDirty(DirtyRect.singleChar(x, y));
    }

    fn printVga(self: *TTY, ch: u8) void {
        self._buffer[self._y * self.width + self._x] = ch;
        self.markCellDirty(self._x, self._y);
        self._x += 1;
        if (self._x >= self.width) {
            self._x = 0;
            self._y += 1;
        }
        if (self._y >= self.height)
            self._scroll();
    }

    fn printChar(self: *TTY, c: u8) void {
        switch (c) {
            '\n'    => {
                self._y += 1;
                self._x = 0;
                if (self._y >= self.height)
                    self._scroll();
            },
            // 3       => {self._y += 1; self._x = 0;},
            8       => self.removeAtCursor(),
            12      => self.clear(),
            '\t'    => self.print("    "),
            else    => self.printVga(c),
        }
    }

    fn home(self: *TTY) void {
        self.markDirty(DirtyRect.init(0, self._y, self._x, self._y));
        self.saveCursor();
        self._x = 0;
        self.render();
    }

    fn endline(self: *TTY) void {
        self.saveCursor();
        const row = self._y * self.width;
        while (self._buffer[row + self._x] != 0 and self._x < self.width - 1)
            self._x += 1;
        self.markDirty(DirtyRect.init(0, self._y, self._x, self._y));
        self.render();
    }

    fn shiftBufferRight(self: *TTY) void {
        var i = self._input_len;
        const pos = self._y * self.width;
        while (i > self._x): (i -= 1) {
            self._buffer[pos + i] = self._buffer[pos + i - 1];
        }
    }

    fn shiftBufferLeft(self: *TTY) void {
        var i = self._x;
        const pos = self._y * self.width;
        while (i < self._input_len -| 1): (i += 1) {
            self._buffer[pos + i] = self._buffer[pos + i + 1];
        }
        self._buffer[pos + self._input_len -| 1] = 0;
    }

    fn insertAtCursor(self: *TTY, c: u8) void {
        if (self._x < self.width - 1) {
            self.shiftBufferRight();
            self._buffer[self._y * self.width + self._x] = c;
            self._input_len += 1;
            self.markDirty(
                DirtyRect.init(
                    self._x,
                    self._y,
                    self._input_len,
                    self._y
                )
            );
            self.saveCursor();
            self._x += 1;
            self.render();
        }
    }

    fn removeAtCursor(self: *TTY) void {
        if (self._x > 0) {
            self.saveCursor();
            self._x -= 1;
            self.shiftBufferLeft();
            self.markDirty(
                DirtyRect.init(
                    self._x,
                    self._y,
                    self._input_len,
                    self._y
                )
            );
            self._input_len -|= 1;
            self.render();
        }
    }

    fn processEnter(self: *TTY) void {
        const pos = self._y * self.width;
        @memcpy(
            self._line[0..self._input_len],
            self._buffer[pos..pos+self._input_len]
        );
        const line: [] const u8 = self._line[0..self._input_len];
        self._input_len = 0;
        self.saveCursor();
        self.printChar('\n');
        self.render();
        if (line.len > 0)
            self.shell.handleInput(line);
    }

    pub fn input(self: *TTY, data: [] const KeyEvent) void {
        for (data) |event| {
            if (!event.ctl) {
                switch (event.val) {
                    '\n' => self.processEnter(),
                    12 => self.clear(),
                    8 => self.removeAtCursor(),
                    else => self.insertAtCursor(event.val), 
                }
            } else {
                const ctl: CtrlType = @enumFromInt(event.val);
                switch (ctl) {
                    .LEFT => self.move(0),
                    .RIGHT => self.move(1),
                    .HOME => self.home(),
                    .END => self.endline(),
                    else => {},
                }
            }
        }
    }

    pub fn print(self: *TTY, msg: [] const u8) void {
        self.saveCursor();
        for (msg) |c| {
            self.printChar(c);
        }
        self.render();
    }

    pub fn setColor(self: *TTY, fg: u32) void {
        self._fg_colour = fg;
    }

    pub fn setBgColor(self: *TTY, bg: u32) void {
        self._bg_colour = bg;
    }
};
