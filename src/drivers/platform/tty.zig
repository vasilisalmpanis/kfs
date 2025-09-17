const krn = @import("kernel");
const io = @import("arch").io;
const scr = @import("../screen.zig");
const kbd = @import("../kbd.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");

// termios
const NCCS: usize = 19;

const WinSize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16 = 0,
    ws_ypixel: u16 = 0    
};

const Termios = extern struct {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [NCCS]u8
};

// c_cc indexes
const VINTR: usize = 0;
const VQUIT: usize = 1;
const VERASE: usize = 2;
const VKILL: usize = 3;
const VEOF: usize = 4;
const VTIME: usize = 5;
const VMIN: usize = 6;
const VSWTC: usize = 7;
const VSTART: usize = 8;
const VSTOP: usize = 9;
const VSUSP: usize = 10;
const VEOL: usize = 11;
const VREPRINT: usize = 12;
const VDISCARD: usize = 13;
const VWERASE: usize = 14;
const VLNEXT: usize = 15;
const VEOL2: usize = 16;

// iflag
const IGNBRK: u32 = 1 << 0;
const BRKINT: u32 = 1 << 1;
const IGNPAR: u32 = 1 << 2;
const PARMRK: u32 = 1 << 3;
const INPCK: u32 = 1 << 4;
const ISTRIP: u32 = 1 << 5;
const INLCR: u32 = 1 << 6;
const IGNCR: u32 = 1 << 7;
const ICRNL: u32 = 1 << 8;
const IUCLC: u32 = 1 << 9;
const IXON: u32 = 1 << 10;
const IXANY: u32 = 1 << 11;
const IXOFF: u32 = 1 << 12;
const IMAXBEL: u32 = 1 << 13;
const IUTF8: u32 = 1 << 14;
// oflag
const OPOST: u32 = 1 << 0;
const OLCUC: u32 = 1 << 1;
const ONLCR: u32 = 1 << 2;
const OCRNL: u32 = 1 << 3;
const ONOCR: u32 = 1 << 4;
const ONLRET: u32 = 1 << 5;
// lflag
const ISIG: u32 = 1 << 0;
const ICANON: u32 = 1 << 1;
const ECHO: u32 = 1 << 3;
const ECHOE: u32 = 1 << 4;
const ECHOK: u32 = 1 << 5;
const ECHONL: u32 = 1 << 6;
const NOFLSH: u32 = 1 << 7;
const TOSTOP: u32 = 1 << 8;
const IEXTEN: u32 = 1 << 15;

// signals
const SIGINT: u32 = 2;
const SIGQUIT: u32 = 3;
const SIGTSTP: u32 = 20;
const SIGWINCH: u32 = 28;

// tty ioctls (subset)
const TCGETS: u32 = 0x5401;
const TCSETS: u32 = 0x5402;
const TCSETSW: u32 = 0x5403;
const TCSETSF: u32 = 0x5404;
const TCSBRK: u32 = 0x5409;
const TCXONC: u32 = 0x540A;
const TCFLSH: u32 = 0x540B;
const TIOCGPGRP: u32 = 0x540F;
const TIOCSPGRP: u32 = 0x5410;
const TIOCOUTQ: u32 = 0x5411;
const TIOCGWINSZ: u32 = 0x5413;
const TIOCSWINSZ: u32 = 0x5414;
const TIOCINQ: u32 = 0x541B;
const TIOCNOTTY: u32 = 0x5422;
const TIOCSCTTY: u32 = 0x540E;
const TIOCGSID: u32 = 0x5429;
const FIONBIO: u32 = 0x5421;
// VT/KD stubs
const VT_OPENQRY: u32 = 0x5600;
const VT_GETSTATE: u32 = 0x5603;
const VT_ACTIVATE: u32 = 0x5606;
const VT_WAITACTIVE: u32 = 0x5607;
const KDGETMODE: u32 = 0x4B3B;
const KDSETMODE: u32 = 0x4B3A;
const KD_TEXT: u32 = 0x00;
const KD_GRAPHICS: u32 = 0x01;

// ---------------------- driver binding
var tty_driver = pdrv.PlatformDriver{
    .driver = drv.Driver{
        .list = undefined,
        .name = "tty",
        .probe = undefined,
        .remove = undefined,
        .fops = &tty_file_ops
    },
    .probe = tty_probe,
    .remove = tty_remove
}
;
var tty_file_ops = krn.fs.FileOps{
    .open = tty_open,
    .close = tty_close,
    .read = tty_read,
    .write = tty_write,
    .lseek = null,
    .readdir = null,
    .ioctl = tty_ioctl
};

// TTY structure
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

pub const DirtyRect = struct {
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,
    pub fn init(x1: u32, y1: u32, x2: u32, y2: u32) DirtyRect {
        return .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2 };
    }
    pub fn fullScreen(w: u32, h: u32) DirtyRect {
        return .{ .x1 = 0, .y1 = 0, .x2 = w - 1, .y2 = h - 1 };
    }
    pub fn singleChar(x: u32, y: u32) DirtyRect {
        return .{ .x1 = x, .y1 = y, .x2 = x, .y2 = y };
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

const ParserState = enum { Normal, Esc, Csi };

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
    _dirty: DirtyRect = DirtyRect.init(0, 0, 0, 0),
    _has_dirty: bool = false,

    // termios & winsize
    term: Termios,
    winsz: WinSize,

    // input queue
    file_buff: krn.ringbuf.RingBuf = undefined,
    lock: krn.Mutex = krn.Mutex.init(),
    nonblock: bool = false,

    // job control
    session_id: i32 = -1,
    fg_pgid: i32 = -1,
    is_controlling: bool = false,

    // vt/kd
    vt_index: u16 = 1,
    vt_active: bool = true,
    kd_mode: u32 = KD_TEXT,

    // editing
    _input_len: u32 = 0,

    // cursor
    show_cursor: bool = true,
    saved_x: u32 = 0,
    saved_y: u32 = 0,

    // SGR attributes (minimal)
    attr_inverse: bool = false,

    // CSI parser state
    pstate: ParserState = .Normal,
    csi_params: [8]u16 = [_]u16{0} ** 8,
    csi_n: u8 = 0,
    csi_priv: bool = false,

    pub fn init(w: u32, h: u32) TTY {
        const buffer: [*]u8 = krn.mm.kmallocArray(u8, w * h) orelse @panic("buffer");
        const prev: [*]u8 = krn.mm.kmallocArray(u8, w * h) orelse @panic("prev_buffer");
        const line: [*]u8 = krn.mm.kmallocArray(u8, w) orelse @panic("line");
        const rb = krn.ringbuf.RingBuf.new(4096) catch @panic("ringbuf");
        var t = TTY{
            .width = w,
            .height = h,
            ._buffer = buffer,
            ._prev_buffer = prev,
            ._line = line,
            .file_buff = rb,
            .lock = krn.Mutex.init(),
            .winsz = WinSize{ .ws_row = @intCast(h), .ws_col = @intCast(w) },
            .term = default_termios(),
        };
        @memset(t._buffer[0 .. w * h], 0);
        @memset(t._prev_buffer[0 .. w * h], 0);
        t.clear();
        return t;
    }

    fn default_termios() Termios {
        var t = Termios{
            .c_iflag = ICRNL | IXON | IUTF8,
            .c_oflag = OPOST | ONLCR,
            .c_cflag = 0,
            .c_lflag = ISIG | ICANON | ECHO | ECHOE | ECHOK | IEXTEN,
            .c_line = 0,
            .c_cc = [_]u8{0} ** NCCS
        };
        t.c_cc[VINTR] = 3;
        t.c_cc[VQUIT] = 28;
        t.c_cc[VERASE] = 127;
        t.c_cc[VKILL] = 21;
        t.c_cc[VEOF] = 4;
        t.c_cc[VTIME] = 0;
        t.c_cc[VMIN] = 1;
        t.c_cc[VSTART] = 17;
        t.c_cc[VSTOP] = 19;
        t.c_cc[VSUSP] = 26;
        t.c_cc[VREPRINT] = 18;
        t.c_cc[VDISCARD] = 15;
        t.c_cc[VWERASE] = 23;
        t.c_cc[VLNEXT] = 22;
        return t;
    }

    fn lflag(self: *TTY, b: u32) bool {
        return (self.term.c_lflag & b) != 0;
    }
    fn iflag(self: *TTY, b: u32) bool {
        return (self.term.c_iflag & b) != 0;
    }
    fn oflag(self: *TTY, b: u32) bool {
        return (self.term.c_oflag & b) != 0;
    }

    fn sendSigPgrp(self: *TTY, sig: u32) void {
        _ = sig;
        if (self.fg_pgid > 0) {
            // krn.task.signalProcessGroup(@intCast(self.fg_pgid), sig) catch {};
        }
    }

    // ------- rendering
    fn renderCursor(self: *TTY) void {
        if (!self.show_cursor) return;
        const off = self._y * self.width + self._x;
        const ch = self._buffer[off];
        // reverse-video cursor, independent of SGR inverse
        scr.framebuffer.putchar(ch, self._x, self._y, self._fg, self._bg);
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
        if (!self._has_dirty and self._x == self._prev_x and self._y == self._prev_y) return;
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
                                const t = bg;
                                bg = fg;
                                fg = t;
                            }
                            scr.framebuffer.putchar(ch, col, row, bg, fg);
                            self._prev_buffer[off] = ch;
                        }
                    }
                }
            }
        }
        // restore previous cell
        const cprev = self._buffer[self._prev_y * self.width + self._prev_x];
        var bg = self._bg;
        var fg = self._fg;
        if (self.attr_inverse) {
            const t = bg;
            bg = fg;
            fg = t;
        }
        scr.framebuffer.putchar(cprev, self._prev_x, self._prev_y, bg, fg);
        self.renderCursor();
        scr.framebuffer.render();
        self._has_dirty = false;
    }

    fn markDirty(self: *TTY, r: DirtyRect) void {
        if (self._has_dirty) self._dirty = self._dirty.merge(r) else {
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
            @memcpy(self._buffer[p - self.width .. p], self._buffer[p .. p + self.width]);
        }
        const p: u32 = self.height * self.width;
        @memset(self._buffer[p - self.width .. p], 0);
        @memset(self._prev_buffer[p - self.width .. p], 1);
        self._y = self.height - 1;
        self._prev_x = self._x;
        self._prev_y = self._y;
        self.markDirty(DirtyRect.fullScreen(self.width, self.height));
    }

    fn clear(self: *TTY) void {
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
        if (self._y >= self.height) self._scroll();
    }

    fn printChar(self: *TTY, c: u8) void {
        switch (c) {
            '\n' => {
                self._y += 1;
                self._x = 0;
                if (self._y >= self.height) self._scroll();
            },
            '\r' => {
                self._prev_x = self._x;
                self._prev_y = self._y;
                self._x = 0;
                self.render();
            },
            8 => self.removeAtCursor(),
            12 => self.clear(),
            '\t' => self.print("    "),
            else => self.printVga(c),
        }
    }

    fn home(self: *TTY) void {
        self.markDirty(DirtyRect.init(0, self._y, self._x, self._y));
        self._prev_x = self._x;
        self._prev_y = self._y;
        self._x = 0;
        self.render();
    }
    fn endline(self: *TTY) void {
        self._prev_x = self._x;
        self._prev_y = self._y;
        const row = self._y * self.width;
        while (self._buffer[row + self._x] != 0 and self._x < self.width - 1) self._x += 1;
        self.markDirty(DirtyRect.init(0, self._y, self._x, self._y));
        self.render();
    }

    fn shiftRight(self: *TTY) void {
        var i = self._input_len;
        const pos = self._y * self.width;
        while (i > self._x) : (i -= 1) self._buffer[pos + i] = self._buffer[pos + i - 1];
    }
    fn shiftLeft(self: *TTY) void {
        if (self._input_len == 0) return;
        var i = self._x;
        const pos = self._y * self.width;
        while (i + 1 < self._input_len and i + 1 < self.width) : (i += 1) {
            self._buffer[pos + i] = self._buffer[pos + i + 1];
        }
        const last = @min(self._input_len - 1, self.width - 1);
        self._buffer[pos + last] = 0;
    }
    fn currentLineLen(self: *TTY) u32 {
        var len: u32 = 0;
        const pos = self._y * self.width;
        while (len < self.width and self._buffer[pos + len] != 0) len += 1;
        return len;
    }

    fn insertAtCursor(self: *TTY, b: u8) void {
        if (self._x < self.width - 1) {
            if (self._input_len == 0) self._input_len = self.currentLineLen();
            self.shiftRight();
            self._buffer[self._y * self.width + self._x] = b;
            if (self._input_len < self.width) self._input_len += 1;
            const end = @min(self.width - 1, self._input_len);
            self.markDirty(DirtyRect.init(self._x, self._y, end, self._y));
            self._prev_x = self._x;
            self._prev_y = self._y;
            self._x += 1;
            self.render();
        }
    }
    fn removeAtCursor(self: *TTY) void {
        if (self._x > 0) {
            if (self._input_len == 0) self._input_len = self.currentLineLen();
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
            const end = if (self._input_len == 0) self._x else @min(self._input_len, self.width - 1);
            self.markDirty(DirtyRect.init(self._x, self._y, end, self._y));
            self.render();
        }
    }

    // ---------- line discipline helpers
    fn translate_input(self: *TTY, b: u8) u8 {
        if (self.iflag(ICRNL) and b == '\r') return '\n';
        if (self.iflag(INLCR) and b == '\n') return '\r';
        if (self.iflag(IGNCR) and b == '\r') return 0;
        return b;
    }
    fn output_nl(self: *TTY) void {
        if (self.oflag(OPOST) and self.oflag(ONLCR)) {
            self.printChar('\r');
            self.printChar('\n');
        } else {
            self.printChar('\n');
        }
    }
    fn echo_if(self: *TTY, b: u8) void {
        if (self.lflag(ECHO)) self.insertAtCursor(b);
    }

    fn push_input(self: *TTY, b: u8) void {
        self.lock.lock();
        _ = self.file_buff.push(b);
        self.lock.unlock();
    }
    fn pushSeq(self: *TTY, s: []const u8) void {
        self.lock.lock();
        _ = self.file_buff.pushSlice(s);
        self.lock.unlock();
    }

    fn handle_isig(self: *TTY, b: u8) bool {
        if (!self.lflag(ISIG)) return false;
        if (b == self.term.c_cc[VINTR] and b != 0) {
            self.sendSigPgrp(SIGINT);
            return true;
        }
        if (b == self.term.c_cc[VQUIT] and b != 0) {
            self.sendSigPgrp(SIGQUIT);
            return true;
        }
        if (b == self.term.c_cc[VSUSP] and b != 0) {
            self.sendSigPgrp(SIGTSTP);
            return true;
        }
        return false;
    }

    fn processEnter(self: *TTY) void {
        self._input_len = 0;
        if (self.lflag(ECHONL) or self.lflag(ECHO))
            self.printChar('\n');
        self.lock.lock();
        _ = self.file_buff.push('\n');
        self.lock.unlock();
    }

    // ---------- INPUT: deliver bytes / sequences
    pub fn input(self: *TTY, data: []const kbd.KeyEvent) void {
        for (data) |event| {
            if (!event.ctl) {
                const b = self.translate_input(event.val);
                if (b == 0)
                    continue;
                if (self.handle_isig(b)) {
                    if (!self.lflag(NOFLSH)) {}
                    continue;
                }
                if (self.lflag(ICANON)) {
                    if (b == '\n') { 
                        self.processEnter(); 
                        continue;
                    }
                    if (b == 8 or b == 127) { // backspace
                        if (self.lflag(ECHO))
                            self.removeAtCursor();
                        self.lock.lock();
                        _ = self.file_buff.unwrite(1);
                        self.lock.unlock();
                        continue;
                    }
                    if (b == 12) { // Ctrl+L
                        // echo as clear on the console; still deliver ^L to app
                        if (self.lflag(ECHO))
                            self.clear();
                        self.push_input(b);
                        continue;
                    }
                    if (b < 32) { // other controls: deliver, but don't draw as glyphs
                        self.push_input(b);
                        continue;
                    }
                    // control bytes: deliver to app, don't draw as glyphs
                    if (b < 32 and b != '\t') {
                        self.push_input(b);
                        continue;
                    }
                    // printable
                    if (self.lflag(ECHO))
                        self.insertAtCursor(b);
                    self.push_input(b);
                } else {
                    // raw: echo glyphs only, and push immediately
                    if (self.lflag(ECHO)) {
                        if (b == '\n' and self.oflag(OPOST) and self.oflag(ONLCR)) self.print("\r\n")
                        else self.printChar(b);
                    }
                    self.push_input(b);
                }
            } else {
                const ctl: kbd.CtrlType = @enumFromInt(event.val);
                if (!self.lflag(ICANON)) {
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
                    // canonical: local cursor movement
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
            if (self._x > 0) self._x -= 1;
        } else {
            if (self._x < self.width - 1 and self._buffer[self._y * self.width + self._x] != 0) self._x += 1;
        }
        self.render();
    }

    pub fn print(self: *TTY, msg: []const u8) void {
        self._prev_x = self._x;
        self._prev_y = self._y;
        for (msg) |c| self.printChar(c);
        self.render();
    }
    pub fn setColor(self: *TTY, fg: u32) void {
        self._fg = fg;
    }
    pub fn setBgColor(self: *TTY, bg: u32) void {
        self._bg = bg;
    }

    // ---------- CSI parser (OUTPUT from apps)
    fn csi_reset(self: *TTY) void {
        self.csi_params = [_]u16{0} ** 8;
        self.csi_n = 0;
        self.csi_priv = false;
    }
    fn csi_accum_digit(self: *TTY, b: u8) void {
        if (self.csi_n == 0) self.csi_n = 1;
        const idx = self.csi_n - 1;
        self.csi_params[idx] = self.csi_params[idx] * 10 + @as(u16, b - '0');
    }
    fn csi_next_param(self: *TTY) void {
        if (self.csi_n == 0) self.csi_n = 1;
        if (self.csi_n < 8) self.csi_n += 1;
    }

    fn param(self: *TTY, i: u8, def: u16) u16 {
        if (self.csi_n == 0)
            return def;
        if (i >= self.csi_n)
            return def;
        const v = self.csi_params[i];
        return if (v == 0) def else v;
    }
    fn csi_finalize_and_act(self: *TTY, final: u8) void {
        switch (final) {
            'A' => { // CUU
                const n = param(self, 0, 1);
                var i: u16 = 0;
                while (i < n and self._y > 0) : (i += 1) self._y -= 1;
                self.render();
            },
            'B' => { // CUD
                const n = param(self, 0, 1);
                var i: u16 = 0;
                while (i < n and self._y < self.height - 1) : (i += 1) self._y += 1;
                self.render();
            },
            'C' => {
                const n = param(self, 0, 1);
                var i: u16 = 0;
                while (i < n and self._x < self.width - 1) : (i += 1) self._x += 1;
                self.render();
            },
            'D' => {
                const n = param(self, 0, 1);
                var i: u16 = 0;
                while (i < n and self._x > 0) : (i += 1) self._x -= 1;
                self.render();
            },
            'H', 'f' => { // CUP/HVP 1-based
                var r = param(self, 0, 1);
                var c = param(self, 1, 1);
                if (r < 1) r = 1;
                if (c < 1) c = 1;
                self._y = @min(@as(u32, r - 1), self.height - 1);
                self._x = @min(@as(u32, c - 1), self.width - 1);
                self.render();
            },
            'J' => { // ED
                const mode = if (self.csi_n == 0) 0 else self.csi_params[0];
                switch (mode) {
                    0 => { // clear from cursor to end of screen
                        self.clearFromCursorToEnd();
                    },
                    1 => { // clear from start to cursor
                        self.clearFromStartToCursor();
                    },
                    else => { // 2
                        self.clear();
                    },
                }
            },
            'K' => { // EL
                const mode = if (self.csi_n == 0) 0 else self.csi_params[0];
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
            'h', 'l' => { // DEC private modes (we only do ?25h/l show cursor)
                if (self.csi_priv) {
                    if (self.csi_n > 0 and self.csi_params[0] == 25) {
                        if (final == 'h') self.show_cursor = true else self.show_cursor = false;
                        self.render();
                    }
                }
            },
            else => {},
        }
        self.pstate = .Normal;
        self.csi_reset();
    }

    fn clearToEol(self: *TTY) void {
        const pos = self._y * self.width;
        var x = self._x;
        while (x < self.width) : (x += 1) self._buffer[pos + x] = 0;
        self.markDirty(DirtyRect.init(self._x, self._y, self.width - 1, self._y));
        self.render();
    }
    fn clearToBol(self: *TTY) void {
        const pos = self._y * self.width;
        var x: u32 = 0;
        while (x <= self._x) : (x += 1) self._buffer[pos + x] = 0;
        self.markDirty(DirtyRect.init(0, self._y, self._x, self._y));
        self.render();
    }
    fn clearLine(self: *TTY) void {
        const pos = self._y * self.width;
        @memset(self._buffer[pos .. pos + self.width], 0);
        self.markDirty(DirtyRect.init(0, self._y, self.width - 1, self._y));
        self.render();
    }
    fn clearFromCursorToEnd(self: *TTY) void { // current line to end then below lines
        self.clearToEol();
        var row = self._y + 1;
        while (row < self.height) : (row += 1) {
            const p = row * self.width;
            @memset(self._buffer[p .. p + self.width], 0);
        }
        self.markDirty(DirtyRect.init(0, self._y, self.width - 1, self.height - 1));
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
        while (x <= self._x) : (x += 1) self._buffer[pos + x] = 0;
        self.markDirty(DirtyRect.init(0, 0, self.width - 1, self._y));
        self.render();
    }

    // consume one byte of OUTPUT (write path)
    fn consume(self: *TTY, b: u8) void {
        switch (self.pstate) {
            .Normal => switch (b) {
                0x1b => self.pstate = .Esc,
                else => self.printChar(b),
            },
            .Esc => switch (b) {
                '[' => {
                    self.csi_reset();
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
                    self.csi_accum_digit(b);
                    return;
                }
                if (b == ';') {
                    self.csi_next_param();
                    return;
                }
                self.csi_finalize_and_act(b);
            },
        }
    }
};

// ---------------------- file ops helpers
fn get_tty(file: *krn.fs.File) !*TTY {
    if (file.inode.data.dev) |_d|
        return @ptrCast(@alignCast(_d.data));
    return krn.errors.PosixError.EIO;
}

fn tty_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {
    krn.logger.WARN("8250 file opened\n", .{});
}

fn tty_close(base: *krn.fs.File) void {
    krn.logger.WARN("tty {s} closed\n", .{base.path.?.dentry.name});
}

fn tty_read(file: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    var tty = try get_tty(file);
    if (tty.lflag(ICANON)) {
        while (!tty.file_buff.hasLine()) {}
        tty.lock.lock();
        defer tty.lock.unlock();
        return @intCast(tty.file_buff.readLineInto(buf[0..size]));
    } else {
        const vmin: u8 = tty.term.c_cc[VMIN];
        while (true) {
            const avail = tty.file_buff.available();
            if (avail == 0) {
                if (vmin == 0 or tty.nonblock) return 0;
                continue;
            }
            const to_read = @min(@as(u32, avail), size);
            tty.lock.lock();
            const n = tty.file_buff.readInto(buf[0..to_read]);
            tty.lock.unlock();
            return @intCast(n);
        }
    }
}

fn tty_write(file: *krn.fs.File, buf: [*]const u8, size: u32) !u32 {
    var tty = try get_tty(file);
    const msg = buf[0..size];
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        const c = msg[i];
        if (c == '\n' and tty.oflag(OPOST) and tty.oflag(ONLCR)) {
            tty.consume('\r');
            tty.consume('\n');
        } else {
            tty.consume(c);
        }
    }
    tty.render();
    return size;
}

// ---------------------- IOCTLs

fn tty_ioctl(file: *krn.fs.File, op: u32, data: ?*anyopaque) !u32 {
    var tty = try get_tty(file);
    switch (op) {
        TCGETS => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TCGETS\n", .{});
                @as(*Termios, @ptrCast(@alignCast(p))).* = tty.term;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TCSETS, TCSETSW, TCSETSF => {
            if (data) |p| {
                const newt: *const Termios = @ptrCast(@alignCast(p));
                krn.logger.DEBUG("tty_ioctl TCSETS, TCSETSW, TCSETSF, new term: {}\n", .{newt.*});
                if (op == TCSETSW or op == TCSETSF) {}
                if (op == TCSETSF) { // flush input queue
                    tty.lock.lock();
                    _ = tty.file_buff.reset();
                    tty.lock.unlock();
                }
                tty.term = newt.*;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TCSBRK => {
            krn.logger.DEBUG("tty_ioctl TCSBRK\n", .{});
            return 0;
        },
        TCXONC => {
            krn.logger.DEBUG("tty_ioctl TCXONC\n", .{});
            return 0;
        },
        TCFLSH => {
            // arg: 0=flush input, 1=flush output, 2=both
            if (data) |p| {
                const arg: u32 = @intFromPtr(p); // user passes small int; logger may show pointer-like
                krn.logger.DEBUG("tty_ioctl TCFLSH {}\n", .{arg});
                switch (arg & 3) {
                    0 => {
                        tty.lock.lock();
                        _ = tty.file_buff.reset();
                        tty.lock.unlock();
                    },
                    1 => {},
                    2 => {
                        tty.lock.lock();
                        _ = tty.file_buff.reset();
                        tty.lock.unlock();
                    },
                    else => {},
                }
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCGWINSZ => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCGWINSZ\n", .{});
                @as(*WinSize, @ptrCast(@alignCast(p))).* = tty.winsz;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSWINSZ => {
            if (data) |p| {
                tty.winsz = @as(*WinSize, @ptrCast(@alignCast(p))).*;
                krn.logger.DEBUG("tty_ioctl TIOCSWINSZ new winsz: {}\n", .{tty.winsz});
                tty.sendSigPgrp(SIGWINCH);
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCINQ => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCINQ\n", .{});
                @as(*u32, @ptrCast(@alignCast(p))).* = @intCast(tty.file_buff.available());
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCOUTQ => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCOUTQ\n", .{});
                @as(*u32, @ptrCast(@alignCast(p))).* = 0;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCGPGRP => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCGPGRP\n", .{});
                @as(*i32, @ptrCast(@alignCast(p))).* = tty.fg_pgid;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSPGRP => {
            if (data) |p| {
                tty.fg_pgid = @as(*i32, @ptrCast(@alignCast(p))).*;
                krn.logger.DEBUG("tty_ioctl TIOCSPGRP new fg_pgid: {d}\n", .{tty.fg_pgid});
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCGSID => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCGSID\n", .{});
                @as(*i32, @ptrCast(@alignCast(p))).* = tty.session_id;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSCTTY => {
            krn.logger.DEBUG("tty_ioctl TIOCSCTTY\n", .{});
            // arg==1 force
            tty.is_controlling = true;
            tty.session_id = 0; // krn.task.current.session_id;
            tty.fg_pgid = krn.task.current.pgid;
            return 0;
        },
        TIOCNOTTY => {
            krn.logger.DEBUG("tty_ioctl TIOCNOTTY\n", .{});
            tty.is_controlling = false;
            return 0;
        },
        FIONBIO => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl FIONBIO\n", .{});
                tty.nonblock = (@as(*i32, @ptrCast(@alignCast(p))).* != 0);
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        // ---- VT/KD stubs ----
        VT_OPENQRY => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl VT_OPENQRY\n", .{});
                @as(*i32, @ptrCast(@alignCast(p))).* = tty.vt_index;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        VT_GETSTATE => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl VT_GETSTATE\n", .{});
                @as(*u16, @ptrCast(@alignCast(p))).* = tty.vt_index;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        VT_ACTIVATE => {
            krn.logger.DEBUG("tty_ioctl VT_ACTIVATE\n", .{});
            tty.vt_active = true;
            return 0;
        },
        VT_WAITACTIVE => {
            krn.logger.DEBUG("tty_ioctl VT_WAITACTIVE\n", .{});
            return 0;
        },
        KDGETMODE => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl KDGETMODE old kd_mode {d}\n", .{tty.kd_mode});
                @as(*u32, @ptrCast(@alignCast(p))).* = tty.kd_mode;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        KDSETMODE => {
            if (data) |p| {
                tty.kd_mode = @as(*u32, @ptrCast(@alignCast(p))).*;
                krn.logger.DEBUG("tty_ioctl KDSETMODE new kd_mode: {d}\n", .{tty.kd_mode});
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        else => return krn.errors.PosixError.EINVAL,
    }
}

// ---------------------- probe / thread / init
fn tty_probe(device: *pdev.PlatformDevice) !void {
    const tty: *TTY = @ptrCast(@alignCast(device.dev.data));
    tty.clear();
    try cdev.addCdev(
        &device.dev,
        krn.fs.UMode{ .usr = 0o6, .grp = 0o6, .other = 0o6 }
    );
}
fn tty_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
    krn.logger.WARN("tty cannot be initialized", .{});
}

pub fn tty_thread(_: ?*const anyopaque) i32 {
    while (krn.task.current.should_stop != true) {
        if (kbd.keyboard.getInput()) |input| {
            scr.current_tty.?.input(input);
        }
    }
    return 0;
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT TTY", .{});
    if (pdev.PlatformDevice.alloc("tty")) |platform_tty| {
        if (krn.mm.kmalloc(TTY)) |tty| {
            tty.* = TTY.init(scr.framebuffer.cwidth, scr.framebuffer.cheight);
            scr.current_tty = tty;
            platform_tty.dev.data = @ptrCast(@alignCast(tty));
        } else return;
        platform_tty.register() catch return;
        krn.logger.WARN("Device registered for tty", .{});
        pdrv.platform_register_driver(&tty_driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver: {any}", .{err});
            return;
        };
        krn.logger.WARN("Driver registered for tty", .{});
        _ = krn.kthreadCreate(&tty_thread, null) catch null;
        return;
    }
    krn.logger.WARN("tty cannot be initialized", .{});
}
