const std = @import("std");
const krn = @import("kernel");

const scr = @import("../screen.zig");
const kbd = @import("../kbd.zig");

const t = @import("./termios.zig");
const tty_drv = @import("tty.zig");

pub const DirtyRect = struct {
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,

    pub fn init(
        x1: u32,
        y1: u32,
        x2: u32,
        y2: u32
    ) DirtyRect {
        return .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2
        };
    }

    pub fn fullScreen(w: u32, h: u32) DirtyRect {
        return .{
            .x1 = 0,
            .y1 = 0,
            .x2 = w - 1,
            .y2 = h - 1
        };
    }

    pub fn singleChar(x: u32, y: u32) DirtyRect {
        return .{
            .x1 = x,
            .y1 = y,
            .x2 = x,
            .y2 = y
        };
    }

    pub fn merge(self: DirtyRect, other: DirtyRect) DirtyRect {
        return .{
            .x1 = @min(self.x1, other.x1),
            .y1 = @min(self.y1, other.y1),
            .x2 = @max(self.x2, other.x2),
            .y2 = @max(self.y2, other.y2)
        };
    }
};

const ParserState = enum {
    Normal,
    Esc,
    Csi
};

const CursorType = enum {
    None,
    Block,
    Underline,
};

pub const WinSize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16 = 0,
    ws_ypixel: u16 = 0    
};

pub const ConsoleColors = enum(u32) {
    Black = 0x000000,
    White = 0x00FFFFFF,
    Red = 0x00FF0000,
    Green = 0x0000FF00,
    Blue = 0x000000FF,
    Yellow = 0x00FFFF00,
    Magenta = 0x00FF00FF,
    Cyan = 0x0000FFFF,
    LightGray = 0x00C6C6C6,
    DarkGray = 0x00868686,
    LightRed = 0x00FF6868,
    LightGreen = 0x0086FF86,
    LightBlue = 0x008686FF,
    LightYellow = 0x00FFFF86,
    LightMagenta = 0x00FF86FF,
    LightCyan = 0x0086FFFF,
    Brown = 0x00868600,
};

pub const TTY = struct {
    width: u32 = 80,
    height: u32 = 25,
    _x: u32 = 0,
    _y: u32 = 0,
    _bg: u32 = @intFromEnum(ConsoleColors.Black),
    _fg: u32 = @intFromEnum(ConsoleColors.White),

    _buffer: [*]u8,
    _prev_buffer: [*]u8,
    _line: [*]u8,
    _prev_x: u32 = 0,
    _prev_y: u32 = 0,
    _dirty: DirtyRect = DirtyRect.init(
        0, 0, 0, 0
    ),
    _has_dirty: bool = false,

    // termios & winsize
    term: t.Termios,
    winsz: WinSize,

    // input queue
    file_buff: krn.ringbuf.RingBuf = undefined,
    lock: krn.Mutex = krn.Mutex.init(),
    nonblock: bool = false,

    // job control
    session_id: i32 = 1,
    fg_pgid: i32 = 1,
    is_controlling: bool = true,

    // vt/kd
    vt_index: u16 = 1,
    vt_active: bool = true,
    kd_mode: u32 = tty_drv.KD_TEXT,

    // editing
    _input_len: u32 = 0,
    tab_len: u32 = 8,

    // cursor
    cursor_type: CursorType = .Block,
    cursor_on: bool = true,
    saved_x: u32 = 0,
    saved_y: u32 = 0,

    // SGR attributes (minimal)
    attr_inverse: bool = false,

    // CSI parser state
    pstate: ParserState = .Normal,
    csi_params: [8]u16 = [_]u16{0} ** 8,
    csi_mask: u8 = 0,
    csi_n: u8 = 0,
    csi_priv: bool = false,

    pub fn init(w: u32, h: u32) TTY {
        const buffer: [*]u8 = krn.mm.kmallocArray(u8, w * h)
            orelse @panic("buffer");
        const prev: [*]u8 = krn.mm.kmallocArray(u8, w * h)
            orelse @panic("prev_buffer");
        const line: [*]u8 = krn.mm.kmallocArray(u8, w)
            orelse @panic("line");
        const rb = krn.ringbuf.RingBuf.new(4096)
            catch @panic("ringbuf");

        var _tty = TTY{
            .width = w,
            .height = h,
            ._buffer = buffer,
            ._prev_buffer = prev,
            ._line = line,
            .file_buff = rb,
            .lock = krn.Mutex.init(),
            .tab_len = 8,
            .winsz = WinSize{
                .ws_row = @intCast(h),
                .ws_col = @intCast(w)
            },
            .term = default_termios(),
        };

        @memset(_tty._buffer[0 .. w * h], 0);
        @memset(_tty._prev_buffer[0 .. w * h], 0);
        _tty.clear();
        return _tty;
    }

    fn default_termios() t.Termios {
        var termios = t.Termios{
            .c_iflag = t.IFlag{
                .ICRNL = true,
                .IXON = true,
                .IUTF8 = true,
            },
            .c_oflag = t.OFlag{
                .OPOST = true,
                .ONLCR = true,
            },
            .c_cflag = 0,
            .c_lflag = t.LFlag{
                .ISIG = true,
                .ICANON = true,
                .ECHO = true,
                .ECHOE = true,
                .ECHOK = true,
                .IEXTEN = true,
            },
            .c_line = 0,
            .c_cc = [_]u8{0} ** t.NCCS
        };
        termios.c_cc[t.VINTR] = 3;
        termios.c_cc[t.VQUIT] = 28;
        termios.c_cc[t.VERASE] = 127;
        termios.c_cc[t.VKILL] = 21;
        termios.c_cc[t.VEOF] = 4;
        termios.c_cc[t.VTIME] = 0;
        termios.c_cc[t.VMIN] = 1;
        termios.c_cc[t.VSTART] = 17;
        termios.c_cc[t.VSTOP] = 19;
        termios.c_cc[t.VSUSP] = 26;
        termios.c_cc[t.VREPRINT] = 18;
        termios.c_cc[t.VDISCARD] = 15;
        termios.c_cc[t.VWERASE] = 23;
        termios.c_cc[t.VLNEXT] = 22;
        return termios;
    }

    pub fn sendSigToProcGrp(
        self: *TTY,
        sig: krn.signals.Signal
    ) void {
        if (self.fg_pgid > 0) {
            _ = krn.kill(
                self.fg_pgid, 
                @intFromEnum(sig)
            ) catch 0;
        }
    }

    // rendering
    fn renderCursor(self: *TTY) void {
        if (self.cursor_type == .None or !self.cursor_on)
            return;
        const off = self._y * self.width + self._x;
        const ch = self._buffer[off];
        if (self.cursor_type == .Underline) {
            scr.framebuffer.cursor(
                self._x,
                self._y,
                self._fg
            );
        } else if (self.cursor_type == .Block) {
            scr.framebuffer.putchar(
                ch,
                self._x,
                self._y,
                self._fg,
                self._bg
            );
        }
    }

    fn saveCursor(self: *TTY) void {
        self.saved_x = self._x;
        self.saved_y = self._y;
    }

    fn restoreCursor(self: *TTY) void {
        self._x = self.saved_x;
        self._y = self.saved_y;
        self.render();
    }

    pub fn reRenderAll(self: *TTY) void {
        scr.framebuffer.clear(self._bg);
        @memset(self._prev_buffer[0 .. self.height * self.width], 0);
        self.markDirty(DirtyRect.fullScreen(self.width, self.height));
        self.render();
    }

    pub fn render(self: *TTY) void {
        if (!self._has_dirty 
            and self._x == self._prev_x
            and self._y == self._prev_y
        ) {
            return;
        }

        if (self._prev_x != self._x or self._prev_y != self._y) {
            const off = self._prev_y * self.width + self._prev_x;
            const ch = self._buffer[off];
            scr.framebuffer.putchar(
                ch,
                self._prev_x,
                self._prev_y,
                self._bg,
                self._fg
            );
            self._prev_buffer[off] = ch;
        }

        if (self._has_dirty) {
            const x1 = self._dirty.x1;
            const y1 = self._dirty.y1;
            const x2 = @min(self._dirty.x2, self.width - 1);
            const y2 = @min(self._dirty.y2, self.height - 1);
            if (x1 <= x2 and y1 <= y2) {
                for (y1..(y2 + 1)) |row| {
                    for (x1..(x2 + 1)) |col| {
                        const off = row * self.width + col;
                        const ch = self._buffer[off];
                        if (ch != self._prev_buffer[off]) {
                            var bg = self._bg;
                            var fg = self._fg;
                            if (self.attr_inverse) {
                                const _tmp = bg;
                                bg = fg;
                                fg = _tmp;
                            }
                            scr.framebuffer.putchar(ch, col, row, bg, fg);
                            self._prev_buffer[off] = ch;
                        }
                    }
                }
            }
        }
        
        self.renderCursor();
        scr.framebuffer.render();
        self._has_dirty = false;
        self._prev_x = self._x;
        self._prev_y = self._y;
    }

    fn markDirty(self: *TTY, r: DirtyRect) void {
        if (self._has_dirty)
            self._dirty = self._dirty.merge(r)
        else {
            self._dirty = r;
            self._has_dirty = true;
        }
    }

    fn markCellDirty(self: *TTY, x: u32, y: u32) void {
        self.markDirty(DirtyRect.singleChar(x, y));
    }

    fn _scroll(self: *TTY) void {
        var i: u32 = 1;
        while (i < self.height) : (i += 1) {
            const p: u32 = i * self.width;
            @memcpy(
                self._buffer[p - self.width .. p],
                self._buffer[p .. p + self.width]
            );
        }
        const p: u32 = self.height * self.width;
        @memset(self._buffer[p - self.width .. p], 0);
        @memset(self._prev_buffer[p - self.width .. p], 1);
        self._y = self.height - 1;
        self._prev_x = self._x;
        self._prev_y = self._y;
        self.markDirty(DirtyRect.fullScreen(self.width, self.height));
    }

    pub fn clear(self: *TTY) void {
        @memset(self._buffer[0 .. self.height * self.width], 0);
        self._x = 0;
        self._y = 0;
        self._prev_x = 0;
        self._prev_y = 0;
        self.markDirty(DirtyRect.fullScreen(self.width, self.height));
        self.render();
    }

    fn printVga(self: *TTY, b: u8) void {
        self._buffer[self._y * self.width + self._x] = b;
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
            '\n' => {
                self._y += 1;
                self._x = 0;
                if (self._y >= self.height)
                    self._scroll();
            },
            '\r' => {
                self._prev_x = self._x;
                self._prev_y = self._y;
                self._x = 0;
                self.render();
            },
            8 => self.move(0),
            12 => self.clear(),
            '\t' => {
                const spaces = self.tab_len - (self._x % self.tab_len);
                self.print("        "[0..spaces]);
            },
            else => self.printVga(c),
        }
    }

    fn home(self: *TTY) void {
        self.markDirty(DirtyRect.init(
            0,
            self._y,
            self._x,
            self._y
        ));
        self._prev_x = self._x;
        self._prev_y = self._y;
        self._x = 0;
        self.render();
    }

    fn endline(self: *TTY) void {
        self._prev_x = self._x;
        self._prev_y = self._y;
        const row = self._y * self.width;
        while (
            self._buffer[row + self._x] != 0
            and self._x < self.width - 1
        ) {
            self._x += 1;
        }
        self.markDirty(DirtyRect.init(
            0,
            self._y,
            self._x,
            self._y
        ));
        self.render();
    }

    fn shiftRight(self: *TTY) void {
        var i = self._input_len;
        const pos = self._y * self.width;
        while (i > self._x) : (i -= 1) {
            self._buffer[pos + i] = self._buffer[pos + i - 1];
        }
    }

    fn shiftLeft(self: *TTY) void {
        if (self._input_len == 0)
            return;
        var i = self._x;
        const pos = self._y * self.width;
        while (
            i + 1 < self._input_len
            and i + 1 < self.width
        ) : (i += 1) {
            self._buffer[pos + i] = self._buffer[pos + i + 1];
        }
        const last = @min(self._input_len - 1, self.width - 1);
        self._buffer[pos + last] = 0;
    }

    fn currentLineLen(self: *TTY) u32 {
        var len: u32 = 0;
        const pos = self._y * self.width;
        while (
            len < self.width
            and self._buffer[pos + len] != 0
        ) {
            len += 1;
        }
        return len;
    }

    fn insertAtCursor(self: *TTY, b: u8) void {
        if (self._x < self.width - 1) {
            if (self._input_len == 0)
                self._input_len = self.currentLineLen();
            self.shiftRight();
            self._buffer[self._y * self.width + self._x] = b;
            if (self._input_len < self.width)
                self._input_len += 1;
            const end = @min(self.width - 1, self._input_len);
            self.markDirty(DirtyRect.init(
                self._x,
                self._y,
                end,
                self._y
            ));
            self._prev_x = self._x;
            self._prev_y = self._y;
            self._x += 1;
            self.render();
        }
    }

    fn removeAtCursor(self: *TTY) void {
        if (self._x > 0) {
            if (self._input_len == 0)   
                self._input_len = self.currentLineLen();
            if (self._input_len == 0) {
                self._prev_x = self._x;
                self._prev_y = self._y;
                self.render();
                return;
            }
            self._prev_x = self._x;
            self._prev_y = self._y;
            self._x -= 1;
            if (self._x < self._input_len) {
                self.shiftLeft();
                self._input_len -= 1;
            } else {
                if (self._input_len > 0) {
                    self._input_len -= 1;
                    const last = @min(self._input_len, self.width - 1);
                    self._buffer[self._y * self.width + last] = 0;
                }
            }
            const end = if (self._input_len == 0) self._x
                else @min(self._input_len, self.width - 1);
            self.markDirty(DirtyRect.init(
                self._x,
                self._y,
                end,
                self._y
            ));
            self.render();
        }
    }

    // line discipline helpers
    fn translateInput(self: *TTY, b: u8) u8 {
        if (self.term.c_iflag.ICRNL and b == '\r')
            return '\n';
        if (self.term.c_iflag.INLCR and b == '\n')
            return '\r';
        if (self.term.c_iflag.IGNCR and b == '\r')
            return 0;
        return b;
    }
    fn outputNL(self: *TTY) void {
        if (self.term.c_oflag.OPOST and self.term.c_oflag.ONLCR) {
            self.printChar('\r');
            self.printChar('\n');
        } else {
            self.printChar('\n');
        }
    }
    fn echoIF(self: *TTY, b: u8) void {
        if (self.term.c_lflag.ECHO)
            self.insertAtCursor(b);
    }

    fn pushInput(self: *TTY, b: u8) void {
        self.lock.lock();
        _ = self.file_buff.push(b);
        self.lock.unlock();
    }

    fn pushSeq(self: *TTY, s: []const u8) void {
        self.lock.lock();
        _ = self.file_buff.pushSlice(s);
        self.lock.unlock();
    }

    fn handleISIG(self: *TTY, b: u8) bool {
        if (!self.term.c_lflag.ISIG)
            return false;
        if (b == self.term.c_cc[t.VINTR] and b != 0) {
            self.sendSigToProcGrp(krn.signals.Signal.SIGINT);
            return true;
        }
        if (b == self.term.c_cc[t.VQUIT] and b != 0) {
            self.sendSigToProcGrp(krn.signals.Signal.SIGQUIT);
            return true;
        }
        if (b == self.term.c_cc[t.VSUSP] and b != 0) {
            self.sendSigToProcGrp(krn.signals.Signal.SIGTSTP);
            return true;
        }
        return false;
    }

    fn processEnter(self: *TTY) void {
        self._input_len = 0;
        if (self.term.c_lflag.ECHONL or self.term.c_lflag.ECHO)
            self.printChar('\n');
        self.lock.lock();
        _ = self.file_buff.push('\n');
        self.lock.unlock();
    }

    pub fn input(self: *TTY, data: []const kbd.KeyEvent) void {
        for (data) |event| {
            if (!event.ctl) {
                const b = self.translateInput(event.val);
                if (b == 0)
                    continue;
                if (self.handleISIG(b)) {
                    if (!self.term.c_lflag.NOFLSH) {
                        self.lock.lock();
                        _ = self.file_buff.reset();
                        self.lock.unlock();
                    }
                    continue;
                }
                if (self.term.c_lflag.ICANON) {
                    if (b == '\n') { 
                        self.processEnter(); 
                        continue;
                    }
                    if (b == 8 or b == 127) { // backspace
                        if (self.term.c_lflag.ECHO)
                            self.removeAtCursor();
                        self.lock.lock();
                        _ = self.file_buff.unwrite(1);
                        self.lock.unlock();
                        continue;
                    }
                    if (b == 12) { // Ctrl+L
                        if (self.term.c_lflag.ECHO)
                            self.clear();
                        self.pushInput(b);
                        continue;
                    }
                    // other controls
                    if (b < 32 and b != '\t') {
                        self.pushInput(b);
                        continue;
                    }
                    // printable
                    if (self.term.c_lflag.ECHO)
                        self.insertAtCursor(b);
                    self.pushInput(b);
                } else {
                    // raw mode
                    if (self.term.c_lflag.ECHO) {
                        if (b == '\n'
                            and self.term.c_oflag.OPOST
                            and self.term.c_oflag.ONLCR
                        ) {
                            self.print("\r\n");
                        } else {
                            self.printChar(b);
                        }
                    }
                    self.pushInput(b);
                }
            } else {
                const ctl: kbd.CtrlType = @enumFromInt(event.val);
                if (!self.term.c_lflag.ICANON) {
                    // raw: send escape sequences matching vt100
                    switch (ctl) {
                        .UP => self.pushSeq("\x1b[A"),
                        .DOWN => self.pushSeq("\x1b[B"),
                        .RIGHT => self.pushSeq("\x1b[C"),
                        .LEFT => self.pushSeq("\x1b[D"),
                        .HOME => self.pushSeq("\x1b[H"),
                        .END => self.pushSeq("\x1b[F"),
                        
                        else => {},
                    }
                } else {
                    // canonical: cursor movement
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
    }

    fn move(self: *TTY, dir: u8) void {
        self._prev_x = self._x;
        self._prev_y = self._y;
        if (dir == 0) {
            if (self._x > 0)
                self._x -= 1;
        } else {
            if (
                self._x < self.width - 1
                and self._buffer[self._y * self.width + self._x] != 0
            ) {
                self._x += 1;
            }
        }
        self.render();
    }

    pub fn print(self: *TTY, msg: []const u8) void {
        self._prev_x = self._x;
        self._prev_y = self._y;
        for (msg) |c| {
            self.printChar(c);
        }
        self.render();
    }

    pub fn setColor(self: *TTY, fg: u32) void {
        self._fg = fg;
    }

    pub fn setBgColor(self: *TTY, bg: u32) void {
        self._bg = bg;
    }

    // CSI parser
    fn csiReset(self: *TTY) void {
        @memset(self.csi_params[0..self.csi_params.len], 0);
        self.csi_mask = 0;
        self.csi_n = 0;
        self.csi_priv = false;
    }

    fn csiAccumDigit(self: *TTY, b: u8) void {
        if (self.csi_n == 0)
            self.csi_n = 1;
        const idx = self.csi_n - 1;
        self.csi_params[idx] = self.csi_params[idx] * 10 + @as(u16, b - '0');
        self.csi_mask |= @as(u8, 1) << @truncate(idx);
    }
    fn csiNextParam(self: *TTY) void {
        if (self.csi_n < 8)
            self.csi_n += 1;
    }

    fn param(self: *TTY, i: u8, def: u16) u16 {
        if (i >= self.csi_n)
            return def;
        if ((self.csi_mask & (@as(u8, 1) << @truncate(i))) == 0) // present but empty
            return def;
        return self.csi_params[i];
    }

    fn csiAct(self: *TTY, final: u8) void {
        switch (final) {
            'A' => { // UP (CUU)
                const n = param(self, 0, 1);
                self._prev_x = self._x;
                self._prev_y = self._y;
                var i: u16 = 0;
                while (i < n and self._y > 0) : (i += 1) {
                    self._y -= 1;
                }
                self.render();
            },
            'B' => { // DOWN (CUD)
                const n = param(self, 0, 1);
                self._prev_x = self._x;
                self._prev_y = self._y;
                var i: u16 = 0;
                while (i < n and self._y < self.height - 1) : (i += 1) {
                    self._y += 1;
                }
                self.render();
            },
            'C' => { // Forward (CUF)
                const n = param(self, 0, 1);
                self._prev_x = self._x;
                self._prev_y = self._y;
                var i: u16 = 0;
                while (i < n and self._x < self.width - 1) : (i += 1) {
                    self._x += 1;
                }
                self.render();
            },
            'D' => { // Back (CUB)
                const n = param(self, 0, 1);
                self._prev_x = self._x;
                self._prev_y = self._y;
                var i: u16 = 0;
                while (i < n and self._x > 0) : (i += 1) {
                    self._x -= 1;
                }
                self.render();
            },
            'H', 'f' => { // CUP/HVP 1-based
                self._prev_x = self._x;
                self._prev_y = self._y;
                var r = param(self, 0, 1);
                var c = param(self, 1, 1);
                if (r < 1)
                    r = 1;
                if (c < 1)
                    c = 1;
                self._y = @min(@as(u32, r - 1), self.height - 1);
                self._x = @min(@as(u32, c - 1), self.width - 1);
                self.render();
            },
            'J' => { // ED
                const mode = if (self.csi_n == 0) 0
                    else self.csi_params[0];
                switch (mode) {
                    0 => {
                        self.clearFromCursorToEnd();
                    },
                    1 => {
                        self.clearFromStartToCursor();
                    },
                    else => {
                        self.clear();
                    },
                }
            },
            'K' => { // EL
                const mode = if (self.csi_n == 0) 0
                    else self.csi_params[0];
                switch (mode) {
                    0 => self.clearToEol(),
                    1 => self.clearToBol(),
                    else => self.clearLine(),
                }
            },
            'm' => { // SGR minimal
                if (self.csi_n == 0) {
                    self.attr_inverse = false;
                }
                var i: u8 = 0;
                while (i < self.csi_n) : (i += 1) {
                    const p = self.csi_params[i];
                    switch (p) {
                        0 => {
                            self.attr_inverse = false;
                        },
                        7 => {
                            self.attr_inverse = true;
                        },
                        27 => {
                            self.attr_inverse = false;
                        },
                        else => {},
                    }
                }
            },
            's' => self.saveCursor(),
            'u' => self.restoreCursor(),
            'h', 'l' => { // DEC private modes
                if (self.csi_priv) {
                    if (self.csi_n > 0 and self.csi_params[0] == 25) {
                        if (final == 'h') {
                            self.cursor_on = true;
                        } else {
                            self.cursor_on = false;
                        }
                        self.render();
                    }
                }
            },
            else => {},
        }
        self.pstate = .Normal;
        self.csiReset();
    }

    fn clearToEol(self: *TTY) void {
        const pos = self._y * self.width;
        var x = self._x;
        while (x < self.width) : (x += 1) {
            self._buffer[pos + x] = 0;
        }
        self.markDirty(DirtyRect.init(
            self._x,
            self._y,
            self.width - 1,
            self._y
        ));
        self.render();
    }

    fn clearToBol(self: *TTY) void {
        const pos = self._y * self.width;
        var x: u32 = 0;
        while (x <= self._x) : (x += 1) {
            self._buffer[pos + x] = 0;
        }
        self.markDirty(DirtyRect.init(
            0,
            self._y,
            self._x,
            self._y
        ));
        self.render();
    }

    fn clearLine(self: *TTY) void {
        const pos = self._y * self.width;
        @memset(self._buffer[pos .. pos + self.width], 0);
        self.markDirty(DirtyRect.init(
            0,
            self._y,
            self.width - 1,
            self._y
        ));
        self.render();
    }

    fn clearFromCursorToEnd(self: *TTY) void {
        self.clearToEol();
        var row = self._y + 1;
        while (row < self.height) : (row += 1) {
            const p = row * self.width;
            @memset(self._buffer[p .. p + self.width], 0);
        }
        self.markDirty(DirtyRect.init(
            0,
            self._y,
            self.width - 1,
            self.height - 1
        ));
        self.render();
    }

    fn clearFromStartToCursor(self: *TTY) void {
        var row: u32 = 0;
        while (row < self._y) : (row += 1) {
            const p = row * self.width;
            @memset(self._buffer[p .. p + self.width], 0);
        }
        const pos = self._y * self.width;
        var x: u32 = 0;
        while (x <= self._x) : (x += 1) {
            self._buffer[pos + x] = 0;
        }
        self.markDirty(DirtyRect.init(
            0,
            0,
            self.width - 1,
            self._y
        ));
        self.render();
    }

    // consume one byte of OUTPUT
    pub fn consume(self: *TTY, b: u8) void {
        switch (self.pstate) {
            .Normal => switch (b) {
                0x1b => self.pstate = .Esc,
                else => self.printChar(b),
            },
            .Esc => switch (b) {
                '[' => {
                    self.csiReset();
                    self.pstate = .Csi;
                },
                '7' => self.saveCursor(),
                '8' => self.restoreCursor(),
                else => self.pstate = .Normal,
            },
            .Csi => {
                if (b == '?') {
                    self.csi_priv = true;
                    return;
                }
                if (b >= '0' and b <= '9') {
                    self.csiAccumDigit(b);
                    return;
                }
                if (b == ';') {
                    self.csiNextParam();
                    return;
                }
                self.csiAct(b);
            },
        }
    }
};
