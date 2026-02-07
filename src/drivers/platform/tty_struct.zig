const std = @import("std");
const krn = @import("kernel");

const scr = @import("../screen.zig");
const kbd = @import("../kbd.zig");
const fb = @import("../framebuffer.zig");

const t = @import("./termios.zig");
const tty_drv = @import("tty.zig");

pub const DirtyRect = struct {
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,

    pub fn init(
        x1: usize,
        y1: usize,
        x2: usize,
        y2: usize
    ) DirtyRect {
        return .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2
        };
    }

    pub fn fullScreen(w: usize, h: usize) DirtyRect {
        return .{
            .x1 = 0,
            .y1 = 0,
            .x2 = w - 1,
            .y2 = h - 1
        };
    }

    pub fn singleChar(x: usize, y: usize) DirtyRect {
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

    pub fn reset(self: *DirtyRect) void {
        self.x1 = 0;
        self.x2 = 0;
        self.y1 = 0;
        self.y2 = 0;
    }
};

const ParserState = enum {
    Normal,
    Esc,
    Csi,
    Osc,
    OscString
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

const AnsiColor = enum(u4) {
    BLACK,
    RED,
    GREEN,
    YELLOW,
    BLUE,
    MAGENTA,
    CYAN,
    WHITE,
    BR_BLACK,
    BR_RED,
    BR_GREEN,
    BR_YELLOW,
    BR_BLUE,
    BR_MAGENTA,
    BR_CYAN,
    BR_WHITE,

    pub fn toU32(self: AnsiColor) u32 {
        return switch (self) {
            .BLACK =>       0x00000000,
            .RED =>         0x00990000,
            .GREEN =>       0x0000A600,
            .YELLOW =>      0x00999900,
            .BLUE =>        0x000000b2,
            .MAGENTA =>     0x00b200b2,
            .CYAN =>        0x0000a6b2,
            .WHITE =>       0x00bfbfbf,
            .BR_BLACK =>    0x00666666,
            .BR_RED =>      0x00e60000,
            .BR_GREEN =>    0x0000d900,
            .BR_YELLOW =>   0x00e6e600,
            .BR_BLUE =>     0x000000FF,
            .BR_MAGENTA =>  0x00e600e6,
            .BR_CYAN =>     0x0000e6e6,
            .BR_WHITE =>    0x00e6e6e6,
        };
    }

    pub fn fromAnsiCode(code: u32) AnsiColor {
        switch (code) {
            30, 40 =>   return .BLACK,
            31, 41 =>   return .RED,
            32, 42 =>   return .GREEN,
            33, 43 =>   return .YELLOW,
            34, 44 =>   return .BLUE,
            35, 45 =>   return .MAGENTA,
            36, 46 =>   return .CYAN,
            37, 47 =>   return .WHITE,
            90, 100 =>  return .BR_BLACK,
            91, 101 =>  return .BR_RED,
            92, 102 =>  return .BR_GREEN,
            93, 103 =>  return .BR_YELLOW,
            94, 104 =>  return .BR_BLUE,
            95, 105 =>  return .BR_MAGENTA,
            96, 106 =>  return .BR_CYAN,
            97, 107 =>  return .BR_WHITE,
            else => return .BLACK,
        }
    }
};

const DEFAULT_FG: u32 = 0x00BFBFBF;
const DEFAULT_BG: u32 = 0x00000000;

fn color256ToRgb(idx: u16) u32 {
    if (idx < 16) {
        // Standard 16 colors
        return AnsiColor.fromAnsiCode(idx + 30).toU32();
    } else if (idx < 232) {
        // 216-color cube (16-231): 6x6x6 RGB
        const cube_idx = idx - 16;
        const r: u32 = @intCast(cube_idx / 36);
        const g: u32 = @intCast((cube_idx % 36) / 6);
        const b: u32 = @intCast(cube_idx % 6);
        const r_val: u32 = if (r == 0) 0 else 55 + r * 40;
        const g_val: u32 = if (g == 0) 0 else 55 + g * 40;
        const b_val: u32 = if (b == 0) 0 else 55 + b * 40;
        return (r_val << 16) | (g_val << 8) | b_val;
    } else {
        // Grayscale (232-255): 24 shades from 8 to 238
        const gray: u32 = @intCast((idx - 232) * 10 + 8);
        return (gray << 16) | (gray << 8) | gray;
    }
}

/// Convert 24-bit RGB components to u32
fn rgbToU32(r: u16, g: u16, b: u16) u32 {
    const r_val: u32 = @intCast(@min(r, 255));
    const g_val: u32 = @intCast(@min(g, 255));
    const b_val: u32 = @intCast(@min(b, 255));
    return (r_val << 16) | (g_val << 8) | b_val;
}

const Cursor = struct {
    kind: CursorType = .Block,
    x: usize = 0,
    y: usize = 0,

    prev_x: usize = 0,
    prev_y: usize = 0,

    drawn: bool = false,
    on: bool = true,

    pub fn init() Cursor {
        return Cursor{};
    }

    pub fn set(self: *Cursor, x: usize, y: usize) void {
        if (self.drawn) {
            self.prev_x = self.x;
            self.prev_y = self.y;
        }
        self.x = x;
        self.y = y;
    }

    pub fn setX(self: *Cursor, x: usize) void {
        self.set(x, self.y);
    }

    pub fn setY(self: *Cursor, y: usize) void {
        self.set(self.x, y);
    }

    pub fn draw(self: *Cursor) void {
        self.drawn = true;
    }
};

const Cell = struct {
    ch: u8 = 0,
    bg: u32,
    fg: u32,

    pub fn eql(self: *const Cell, other: *const Cell) bool {
        return (
            self.ch == other.ch
            and self.bg == other.bg
            and self.fg == other.fg
        );
    }

    pub fn isEmpty(self: *const Cell) bool {
        return self.ch == 0;
    }

    pub fn makeEmpty(self: *Cell) void {
        self.ch = 0;
        self.bg = DEFAULT_BG;
        self.fg = DEFAULT_FG;
    }

    pub fn clear(self: *Cell, bg: u32, fg: u32) void {
        self.ch = 0;
        self.bg = bg;
        self.fg = fg;
    }

    pub fn invert(self: *Cell) void {
        const _bg = self.bg;
        self.bg = self.fg;
        self.fg = _bg;
    }
};

const Page = struct {
    width: usize,
    height: usize,
    buff: [*]Cell,
    prev: [*]Cell,

    curr_fg: u32 = DEFAULT_FG,
    curr_bg: u32 = DEFAULT_BG,
    inverse: bool = false,

    dirty: DirtyRect = DirtyRect.init(0, 0, 0, 0),
    has_dirty: bool = false,

    cursor: Cursor = Cursor.init(),

    pub fn init(w: usize, h: usize) !Page {
        const buff: [*]Cell = @ptrCast(@alignCast(
            krn.mm.kmallocArray(Cell, w * h)
            orelse return krn.errors.PosixError.ENOMEM
        ));
        const prev: [*]Cell = @ptrCast(@alignCast(
            krn.mm.kmallocArray(Cell, w * h)
            orelse return krn.errors.PosixError.ENOMEM
        ));
        const page = Page {
            .width = w,
            .height = h,
            .buff = buff,
            .prev = prev,
        };
        @memset(
            page.buff[0..w * h],
            Cell{ .bg = DEFAULT_BG, .fg = DEFAULT_FG, .ch = 0 }
        );
        @memset(
            page.prev[0..w * h],
            Cell{ .bg = DEFAULT_BG, .fg = DEFAULT_FG, .ch = 0 }
        );
        return page;
    }

    pub fn getCh(self: *Page, x: usize, y: usize) u8 {
        return self.buff[y * self.width + x].ch;
    }

    pub fn getCell(self: *Page, x: usize, y: usize) *Cell {
        return &self.buff[y * self.width + x];
    }

    pub fn getCurrCell(self: *Page) *Cell {
        return self.getCell(self.cursor.x, self.cursor.y);
    }

    pub fn setCursor(self: *Page, x: usize, y: usize) void {
        if (self.cursor.drawn) {
            self.markCellDirty(self.cursor.x, self.cursor.y);
            const off = self.cursor.y * self.width + self.cursor.x;
            self.prev[off].ch = 0xFF;
        }
        self.cursor.set(x, y);
    }

    pub fn setCursorX(self: *Page, x: usize) void {
        self.setCursor(x, self.cursor.y);
    }

    pub fn setCursorY(self: *Page, y: usize) void {
        self.setCursor(self.cursor.x, y);
    }

    fn restorePrevCursorPos(self: *Page) void {
        if (!self.cursor.drawn)
            return;
        if (
            self.cursor.prev_x >= self.width
            or self.cursor.prev_y >= self.height
        ) {
            return;
        }
        const cell = self.getCell(self.cursor.prev_x, self.cursor.prev_y);
        scr.framebuffer.putchar(
            cell.ch,
            self.cursor.prev_x,
            self.cursor.prev_y,
            cell.bg,
            cell.fg,
        );
    }

    fn renderCursor(self: *Page) void {
        if (self.cursor.kind == .None or !self.cursor.on)
            return;
        if (
            self.cursor.x >= self.width
            or self.cursor.y >= self.height
        ) {
            return;
        }
        self.restorePrevCursorPos();
        if (self.cursor.kind == .Underline) {
            scr.framebuffer.cursor(
                self.cursor.x,
                self.cursor.y,
                self.curr_fg,
            );
        } else if (self.cursor.kind == .Block) {
            const cell = self.getCell(self.cursor.x, self.cursor.y);
            const ch = if (cell.ch == 0) ' ' else cell.ch;
            scr.framebuffer.putchar(
                ch,
                self.cursor.x,
                self.cursor.y,
                cell.fg,
                cell.bg,
            );
        }
        self.cursor.drawn = true;
    }

    pub fn render(self: *Page) void {
        if (self.has_dirty) {
            const x1 = self.dirty.x1;
            const y1 = self.dirty.y1;
            const x2 = @min(self.dirty.x2, self.width - 1);
            const y2 = @min(self.dirty.y2, self.height - 1);
            if (x1 <= x2 and y1 <= y2) {
                for (y1..(y2 + 1)) |row| {
                    for (x1..(x2 + 1)) |col| {
                        const off = row * self.width + col;
                        const cell = self.buff[off];
                        if (!cell.eql(&self.prev[off])) {
                            if (cell.isEmpty()) {
                                scr.framebuffer.clearChar(
                                    col, row,
                                    cell.bg
                                );
                            } else {
                                scr.framebuffer.putchar(
                                    cell.ch,
                                    col,
                                    row,
                                    cell.bg,
                                    cell.fg,
                                );
                            }
                            self.prev[off] = cell;
                        }
                    }
                }
            }
        }
        self.renderCursor();
        self.has_dirty = false;
        self.dirty.reset();
    }

    fn markDirty(self: *Page, r: DirtyRect) void {
        if (self.has_dirty)
            self.dirty = self.dirty.merge(r)
        else {
            self.dirty = r;
            self.has_dirty = true;
        }
    }

    fn markCellDirty(self: *Page, x: usize, y: usize) void {
        self.markDirty(DirtyRect.singleChar(x, y));
    }

    pub fn scroll(
        self: *Page,
        lines: usize,
        direction: fb.ScrollDirection
    ) void {
        if (lines == 0)
            return;
        if (lines >= self.height) {
            self.clearScreen();
            return;
        }
        const pos = self.width * lines;
        const end = self.width * self.height;
        const kept_size = end - pos;
        const empty_cell = Cell{ .bg = self.curr_bg, .fg = self.curr_fg, .ch = 0 };

        switch (direction) {
            .up => {
                @memmove(self.buff[0..kept_size], self.buff[pos..end]);
                @memset(self.buff[kept_size..end], empty_cell);
                @memmove(self.prev[0..kept_size], self.prev[pos..end]);
                @memset(self.prev[kept_size..end], empty_cell);
            },
            .down => {
                @memmove(self.buff[pos..end], self.buff[0..kept_size]);
                @memset(self.buff[0..pos], empty_cell);
                @memmove(self.prev[pos..end], self.prev[0..kept_size]);
                @memset(self.prev[0..pos], empty_cell);
            },
        }

        // Scroll the pixel buffer
        const pixel_lines = lines * scr.framebuffer.font.height;
        scr.framebuffer.scrollPixels(
            pixel_lines,
            direction,
            self.curr_bg
        );

        if (self.cursor.drawn) {
            self.cleanupScrolledCursor(lines, direction);
        }
        self.cursor.drawn = false;

        const dirty_rect = switch (direction) {
            .up => DirtyRect.init(
                0,
                self.height - lines,
                self.width - 1,
                self.height - 1
            ),
            .down => DirtyRect.init(
                0,
                0,
                self.width - 1,
                lines - 1
            ),
        };
        self.markDirty(dirty_rect);
    }

    fn cleanupScrolledCursor(
        self: *Page,
        lines: usize,
        direction: fb.ScrollDirection
    ) void {
        switch (direction) {
            .up => {
                if (self.cursor.prev_y >= lines) {
                    const scrolled_y = self.cursor.prev_y - lines;
                    self.redrawCell(self.cursor.prev_x, scrolled_y);
                }
                if (self.cursor.y >= lines) {
                    const scrolled_y = self.cursor.y - lines;
                    self.redrawCell(self.cursor.x, scrolled_y);
                }
            },
            .down => {
                if (self.cursor.prev_y + lines < self.height) {
                    const scrolled_y = self.cursor.prev_y + lines;
                    self.redrawCell(self.cursor.prev_x, scrolled_y);
                }
                if (self.cursor.y + lines < self.height) {
                    const scrolled_y = self.cursor.y + lines;
                    self.redrawCell(self.cursor.x, scrolled_y);
                }
            },
        }
    }

    fn redrawCell(self: *Page, x: usize, y: usize) void {
        const cell = self.getCell(x, y);
        scr.framebuffer.putchar(
            cell.ch, x, y, cell.bg, cell.fg
        );
    }

    pub fn scrollUp(self: *Page, lines: usize) void {
        self.scroll(lines, .up);
    }

    pub fn scrollDown(self: *Page, lines: usize) void {
        self.scroll(lines, .down);
    }

    pub fn reRenderAll(self: *Page) void {
        scr.framebuffer.clear(self.curr_bg);
        @memset(
            self.prev[0..self.height * self.width],
            Cell{ .bg = self.curr_bg, .fg = self.curr_fg, .ch = 0 }
        );
        self.markDirty(
            DirtyRect.fullScreen(self.width, self.height)
        );
        self.render();
    }

    pub fn setColors(self: *Page, fg: u32, bg: u32) void {
        self.curr_bg = bg;
        self.curr_fg = fg;
    }

    pub fn clear(self: *Page) void {
        @memset(
            self.buff[0..self.height * self.width],
            Cell{ .bg = self.curr_bg, .fg = self.curr_fg, .ch = 0 }
        );
        self.setCursor(0, 0);
        self.markDirty(
            DirtyRect.fullScreen(self.width, self.height)
        );
        self.render();
    }

    pub fn clearScreen(self: *Page) void {
        @memset(
            self.buff[0..self.height * self.width],
            Cell{ .bg = self.curr_bg, .fg = self.curr_fg, .ch = 0 }
        );
        self.markDirty(
            DirtyRect.fullScreen(self.width, self.height)
        );
        self.render();
    }

    fn wrapLine(self: *Page) void {
        const new_y = self.cursor.y + 1;
        if (new_y >= self.height) {
            self.scrollUp(1);
            self.setCursor(0, self.height - 1);
        } else {
            self.setCursor(0, new_y);
        }
    }

    fn printChar(self: *Page, ch: u8) void {
        const cell = self.getCurrCell();
        cell.ch = ch;
        cell.fg = if (self.inverse) self.curr_bg else self.curr_fg;
        cell.bg = if (self.inverse) self.curr_fg else self.curr_bg;
        self.markCellDirty(self.cursor.x, self.cursor.y);
        self.setCursorX(self.cursor.x + 1);
        if (self.cursor.x >= self.width) {
            self.wrapLine();
        }
    }

    pub fn endlineXPos(self: *Page) usize {
        var x = self.cursor.x;
        while (x < self.width) {
            if (self.getCell(x, self.cursor.y).isEmpty())
                break ;
            x += 1;
        }
        return x;        
    }
};

pub const TTY = struct {
    width: usize = 80,
    height: usize = 25,

    main_page: Page,
    alt_page: Page,
    curr_page: *Page,
    use_alt_screen: bool = false,

    // termios & winsize
    term: t.Termios,
    winsz: WinSize,

    // input queue
    file_buff: krn.ringbuf.RingBuf = undefined,
    lock: krn.Mutex = krn.Mutex.init(),
    nonblock: bool = false,
    read_queue: krn.wq.WaitQueueHead = undefined,

    // job control
    session_id: i32 = 1,
    fg_pgid: i32 = 1,
    is_controlling: bool = true,

    // vt/kd
    vt_index: u16 = 1,
    vt_active: bool = true,
    kd_mode: u32 = tty_drv.KD_TEXT,

    // editing
    _input_len: usize = 0,
    tab_len: usize = 8,

    // cursor save/restore
    saved_x: usize = 0,
    saved_y: usize = 0,

    // CSI parser state
    pstate: ParserState = .Normal,
    csi_params: [8]u16 = [_]u16{0} ** 8,
    csi_mask: u8 = 0,
    csi_n: u8 = 0,
    csi_priv: bool = false,

    pub fn init(w: usize, h: usize, vt_idx: u16) !TTY {
        const rb = try krn.ringbuf.RingBuf.new(4096);
        const _tty = TTY{
            .width = w,
            .height = h,
            .main_page = try Page.init(w, h),
            .alt_page = try Page.init(w, h),
            .curr_page = undefined,

            .file_buff = rb,
            .lock = krn.Mutex.init(),
            .read_queue = krn.wq.WaitQueueHead.init(),
            .tab_len = 8,
            .winsz = WinSize{
                .ws_row = @intCast(h),
                .ws_col = @intCast(w)
            },
            .term = default_termios(),
            .vt_index = vt_idx,
        };
        return _tty;
    }

    pub fn setup(self: *TTY) void {
        self.curr_page = &self.main_page;
        self.curr_page.clear();
        self.read_queue.setup();
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
            krn.logger.DEBUG(
                "TTY {x}: Sending signal {s} to process group {d}\n",
                .{@intFromPtr(self), @tagName(sig), self.fg_pgid}
            );
            _ = krn.kill(
                self.fg_pgid, 
                @intFromEnum(sig)
            ) catch 0;
        } else {
            krn.logger.WARN(
                "TTY: Cannot send signal {s}, fg_pgid is {d}\n",
                .{@tagName(sig), self.fg_pgid}
            );
        }
    }

    pub fn render(self: *TTY) void {
        if (scr.current_tty) |curr| {
            if (self != curr)
                return ;
        }
        self.curr_page.render();
    }

    fn saveCursor(self: *TTY) void {
        self.saved_x = self.curr_page.cursor.x;
        self.saved_y = self.curr_page.cursor.y;
    }

    fn restoreCursor(self: *TTY) void {
        self.curr_page.setCursor(self.saved_x, self.saved_y);
        self.render();
    }

    fn printChar(self: *TTY, c: u8) void {
        switch (c) {
            '\n' => {
                self.curr_page.wrapLine();
            },
            '\r' => {
                self.curr_page.setCursorX(0);
                self.render();
            },
            7 => {},
            8 => self.move(0),
            12 => self.clear(),
            '\t' => {
                const spaces = self.tab_len - (self.curr_page.cursor.x % self.tab_len);
                self.print("        "[0..spaces]);
            },
            else => self.curr_page.printChar(c),
        }
    }

    fn home(self: *TTY) void {
        self.curr_page.setCursorX(0);
        self.curr_page.render();
    }

    fn endline(self: *TTY) void {
        self.curr_page.setCursorX(self.curr_page.endlineXPos());
        self.curr_page.render();
    }

    fn shiftRight(self: *TTY) void {
        var i = self._input_len;
        const y = self.curr_page.cursor.y;
        while (i > self.curr_page.cursor.x) : (i -= 1) {
            const curr_cell = self.curr_page.getCell(i, y);
            const prev_cell = self.curr_page.getCell(i - 1, y);
            curr_cell.* = prev_cell.*;
        }
    }

    fn shiftLeft(self: *TTY) void {
        if (self._input_len == 0)
            return;
        var i = self.curr_page.cursor.x;
        const y = self.curr_page.cursor.y;
        while (
            i + 1 < self._input_len
            and i + 1 < self.width
        ) : (i += 1) {
            const curr_cell = self.curr_page.getCell(i, y);
            const next_cell = self.curr_page.getCell(i + 1, y);
            curr_cell.* = next_cell.*;
        }
        const last = @min(self._input_len - 1, self.width - 1);
        self.curr_page.getCell(last, y).clear(
            self.curr_page.curr_bg,
            self.curr_page.curr_fg
        );
    }

    fn currentLineLen(self: *TTY) usize {
        var len: usize = 0;
        const y = self.curr_page.cursor.y;
        while (len < self.width) {
            const cell = self.curr_page.getCell(len, y);
            if (cell.isEmpty())
                break;
            len += 1;
        }
        return len;
    }

    fn insertAtCursor(self: *TTY, b: u8) void {
        const x = self.curr_page.cursor.x;
        const y = self.curr_page.cursor.y;
        if (x < self.width - 1) {
            if (self._input_len == 0)
                self._input_len = self.currentLineLen();
            self.shiftRight();
            const cell = self.curr_page.getCell(x, y);
            cell.ch = b;
            cell.fg = self.curr_page.curr_fg;
            cell.bg = self.curr_page.curr_bg;
            if (self._input_len < self.width)
                self._input_len += 1;
            const end = @min(self.width - 1, self._input_len);
            self.curr_page.markDirty(DirtyRect.init(x, y, end, y));
            self.curr_page.setCursorX(x + 1);
            self.render();
        }
    }

    fn removeAtCursor(self: *TTY) void {
        const x = self.curr_page.cursor.x;
        const y = self.curr_page.cursor.y;
        if (x > 0) {
            if (self._input_len == 0)
                self._input_len = self.currentLineLen();
            if (self._input_len == 0) {
                self.render();
                return;
            }
            self.curr_page.setCursorX(x - 1);
            if (x - 1 < self._input_len) {
                self.shiftLeft();
                self._input_len -= 1;
            } else {
                if (self._input_len > 0) {
                    self._input_len -= 1;
                    const last = @min(self._input_len, self.width - 1);
                    self.curr_page.getCell(last, y).clear(
                        self.curr_page.curr_bg,
                        self.curr_page.curr_fg
                    );
                }
            }
            const end = if (self._input_len == 0) x - 1
                else @min(self._input_len, self.width - 1);
            self.curr_page.markDirty(DirtyRect.init(x - 1, y, end, y));
            self.render();
        }
    }

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
        self.read_queue.wakeUpOne();
    }

    fn pushSeq(self: *TTY, s: []const u8) void {
        self.lock.lock();
        _ = self.file_buff.pushSlice(s);
        self.lock.unlock();
        self.read_queue.wakeUpOne();
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
        self.read_queue.wakeUpOne();
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
                    if (b == self.term.c_cc[t.VEOF] and b != 0) {
                        self._input_len = 0;
                        self.lock.lock();
                        _ = self.file_buff.push('\n');
                        self.lock.unlock();
                        self.read_queue.wakeUpOne();
                        continue;
                    }
                    if (b == self.term.c_cc[t.VKILL] and b != 0) {
                        const line_len = self.currentLineLen();
                        if (line_len > 0) {
                            if (self.term.c_lflag.ECHO) {
                                var i: usize = 0;
                                while (i < line_len) : (i += 1) {
                                    self.removeAtCursor();
                                }
                            }
                            self.lock.lock();
                            _ = self.file_buff.unwrite(line_len);
                            self.lock.unlock();
                            self._input_len = 0;
                        }
                        continue;
                    }
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
                        .PGUP => self.pushSeq("\x1b[5~"),
                        .PGDN => self.pushSeq("\x1b[6~"),
                        .INSERT => self.pushSeq("\x1b[2~"),
                        .DELETE => self.pushSeq("\x1b[3~"),
                        
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
        const x = self.curr_page.cursor.x;
        if (dir == 0) {
            if (x > 0)
                self.curr_page.setCursorX(x - 1);
        } else {
            const cell = self.curr_page.getCell(x, self.curr_page.cursor.y);
            if (x < self.width - 1 and !cell.isEmpty()) {
                self.curr_page.setCursorX(x + 1);
            }
        }
        self.render();
    }

    pub fn print(self: *TTY, msg: []const u8) void {
        for (msg) |c| {
            self.printChar(c);
        }
        self.render();
    }

    pub fn setColor(self: *TTY, fg: AnsiColor) void {
        self.curr_page.curr_fg = fg;
    }

    pub fn setBgColor(self: *TTY, bg: AnsiColor) void {
        self.curr_page.curr_bg = bg;
    }

    pub fn clear(self: *TTY) void {
        self.curr_page.clear();
    }

    pub fn reRenderAll(self: *TTY) void {
        self.curr_page.reRenderAll();
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

    fn switchToAltScreen(self: *TTY) void {
        if (!self.use_alt_screen) {
            self.use_alt_screen = true;
            self.curr_page = &self.alt_page;
            self.reRenderAll();
        }
    }

    fn switchToMainScreen(self: *TTY) void {
        if (self.use_alt_screen) {
            self.use_alt_screen = false;
            self.curr_page = &self.main_page;
            self.reRenderAll();
        }
    }

    fn csiAct(self: *TTY, final: u8) void {
        switch (final) {
            'A' => { // UP (CUU)
                const n = self.param(0, 1);
                const new_y = if (self.curr_page.cursor.y >= n)
                    self.curr_page.cursor.y - n
                else
                    0;
                self.curr_page.setCursorY(@intCast(new_y));
                self.render();
            },
            'B' => { // DOWN (CUD)
                const n = self.param(0, 1);
                const new_y = @min(self.curr_page.cursor.y + n, self.height - 1);
                self.curr_page.setCursorY(new_y);
                self.render();
            },
            'C' => { // Forward (CUF)
                const n = self.param(0, 1);
                const new_x = @min(self.curr_page.cursor.x + n, self.width - 1);
                self.curr_page.setCursorX(new_x);
                self.render();
            },
            'D' => { // Back (CUB)
                const n = self.param(0, 1);
                const new_x = if (self.curr_page.cursor.x >= n)
                    self.curr_page.cursor.x - n
                else
                    0;
                self.curr_page.setCursorX(@intCast(new_x));
                self.render();
            },
            'E' => { // Cursor Next Line (CNL)
                const n = self.param(0, 1);
                const new_y = @min(self.curr_page.cursor.y + n, self.height - 1);
                self.curr_page.setCursor(0, new_y);
                self.render();
            },
            'F' => { // Cursor Previous Line (CPL)
                const n = self.param(0, 1);
                const new_y = if (self.curr_page.cursor.y >= n)
                    self.curr_page.cursor.y - n
                else
                    0;
                self.curr_page.setCursor(0, @intCast(new_y));
                self.render();
            },
            'G' => { // Cursor Horizontal Absolute (CHA)
                const col = self.param(0, 1);
                self.curr_page.setCursorX(@min(
                    if (col > 0) col - 1 else 0,
                    self.width - 1
                ));
                self.render();
            },
            'H', 'f' => { // CUP/HVP 1-based
                var r = self.param(0, 1);
                var c = self.param(1, 1);
                if (r < 1)
                    r = 1;
                if (c < 1)
                    c = 1;
                const y = @min(@as(usize, r - 1), self.height - 1);
                const x = @min(@as(usize, c - 1), self.width - 1);
                self.curr_page.setCursor(x, y);
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
                        self.clearScreen();
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
            'L' => { // Insert Lines (IL)
                const n = self.param(0, 1);
                self.insertLines(@intCast(n));
            },
            'M' => { // Delete Lines (DL)
                const n = self.param(0, 1);
                self.deleteLines(@intCast(n));
            },
            'P' => { // Delete Character (DCH)
                const n = self.param(0, 1);
                self.deleteChars(@intCast(n));
            },
            '@' => { // Insert Character (ICH)
                const n = self.param(0, 1);
                self.insertChars(@intCast(n));
            },
            'S' => { // Scroll Up (SU)
                const n = self.param(0, 1);
                self.curr_page.scrollUp(@intCast(n));
                self.render();
            },
            'T' => { // Scroll Down (SD)
                const n = self.param(0, 1);
                self.scrollDown(@intCast(n));
            },
            'd' => { // VPA
                const row = self.param(0, 1);
                self.curr_page.setCursorY(@min(
                    if (row > 0) row - 1 else 0,
                    self.height - 1
                ));
                self.render();
            },
            'n' => { // DSR
                const mode = self.param(0, 0);
                if (mode == 6) {
                    self.reportCursorPosition();
                }
            },
            'r' => { // Set Scrolling Region (DECSTBM)
                // TODO
            },
            'm' => { // SGR with full color support
                if (self.csi_n == 0) {
                    self.curr_page.curr_fg = DEFAULT_FG;
                    self.curr_page.curr_bg = DEFAULT_BG;
                    self.curr_page.inverse = false;
                }
                var i: u8 = 0;
                while (i < self.csi_n) : (i += 1) {
                    const p = self.csi_params[i];
                    switch (p) {
                        0 => {
                            self.curr_page.curr_fg = DEFAULT_FG;
                            self.curr_page.curr_bg = DEFAULT_BG;
                            self.curr_page.inverse = false;
                        },
                        1, 2, 3, 4, 5, 6 => {
                            // Bold, dim, italic, underline, blink, rapid blink
                            // TODO
                        },
                        7 => {
                            self.curr_page.inverse = true;
                        },
                        8, 9 => {
                            // Hidden, strikethrough
                            // TODO
                        },
                        21, 22, 23, 24, 25, 28, 29 => {
                            // Reset bold/dim, italic, underline, blink, hidden, strikethrough
                            // TODO
                        },
                        27 => {
                            self.curr_page.inverse = false;
                        },
                        // Foreground colors
                        30...37 => {
                            self.curr_page.curr_fg = AnsiColor.fromAnsiCode(p).toU32();
                        },
                        38 => {
                            // Extended foreground color: 38;5;N or 38;2;R;G;B
                            if (i + 1 < self.csi_n) {
                                const mode = self.csi_params[i + 1];
                                if (mode == 5 and i + 2 < self.csi_n) {
                                    // 256-color mode: 38;5;N
                                    const color_idx = self.csi_params[i + 2];
                                    self.curr_page.curr_fg = color256ToRgb(color_idx);
                                    i += 2;
                                } else if (mode == 2 and i + 4 < self.csi_n) {
                                    // 24-bit color: 38;2;R;G;B
                                    const r = self.csi_params[i + 2];
                                    const g = self.csi_params[i + 3];
                                    const b = self.csi_params[i + 4];
                                    self.curr_page.curr_fg = rgbToU32(r, g, b);
                                    i += 4;
                                }
                            }
                        },
                        39 => {
                            self.curr_page.curr_fg = DEFAULT_FG;
                        },
                        // Background colors
                        40...47 => {
                            const color = AnsiColor.fromAnsiCode(p).toU32();
                            self.curr_page.curr_bg = color;
                        },
                        48 => {
                            // Extended background color: 48;5;N or 48;2;R;G;B
                            if (i + 1 < self.csi_n) {
                                const mode = self.csi_params[i + 1];
                                if (mode == 5 and i + 2 < self.csi_n) {
                                    // 256-color mode: 48;5;N
                                    const color_idx = self.csi_params[i + 2];
                                    self.curr_page.curr_bg = color256ToRgb(color_idx);
                                    i += 2;
                                } else if (mode == 2 and i + 4 < self.csi_n) {
                                    // 24-bit color: 48;2;R;G;B
                                    const r = self.csi_params[i + 2];
                                    const g = self.csi_params[i + 3];
                                    const b = self.csi_params[i + 4];
                                    self.curr_page.curr_bg = rgbToU32(r, g, b);
                                    i += 4;
                                }
                            }
                        },
                        49 => {
                            self.curr_page.curr_bg = DEFAULT_BG;
                        },
                        // Bright foreground colors
                        90...97 => {
                            self.curr_page.curr_fg = AnsiColor.fromAnsiCode(p).toU32();
                        },
                        // Bright background colors
                        100...107 => {
                            self.curr_page.curr_bg = AnsiColor.fromAnsiCode(p).toU32();
                        },
                        else => {},
                    }
                }
            },
            's' => self.saveCursor(),
            'u' => self.restoreCursor(),
            'h', 'l' => { // DEC private modes
                if (self.csi_priv) {
                    if (self.csi_n > 0) {
                        const mode = self.csi_params[0];
                        switch (mode) {
                            1 => {
                                // DECCKM - Application cursor keys: TODO
                            },
                            7 => {
                                // DECAWM - Auto-wrap mode: TODO
                            },
                            12 => {
                                // Cursor blinking: TODO
                            },
                            25 => {
                                // Cursor visibility
                                self.curr_page.cursor.on = (final == 'h');
                                self.render();
                            },
                            1000, 1002, 1003, 1006, 1015 => {
                                // Mouse tracking modes: TODO
                            },
                            1049 => {
                                // Alt screen buffer
                                if (final == 'h') {
                                    self.saveCursor();
                                    self.switchToAltScreen();
                                } else {
                                    self.switchToMainScreen();
                                    self.restoreCursor();
                                }
                            },
                            47, 1047 => {
                                // Alt screen buffer (without cursor save)
                                if (final == 'h') {
                                    self.switchToAltScreen();
                                } else {
                                    self.switchToMainScreen();
                                }
                            },
                            2004 => {
                                // Bracketed paste mode: TODO
                            },
                            else => {},
                        }
                    }
                }
            },
            else => {},
        }
        self.pstate = .Normal;
        self.csiReset();
    }

    fn clearToEol(self: *TTY) void {
        const y = self.curr_page.cursor.y;
        var x = self.curr_page.cursor.x;
        while (x < self.width) : (x += 1) {
            self.curr_page.getCell(x, y).clear(
                self.curr_page.curr_bg,
                self.curr_page.curr_fg
            );
        }
        self.curr_page.markDirty(DirtyRect.init(
            self.curr_page.cursor.x,
            y,
            self.width - 1,
            y
        ));
        self.render();
    }

    fn clearToBol(self: *TTY) void {
        const y = self.curr_page.cursor.y;
        var x: usize = 0;
        while (x <= self.curr_page.cursor.x) : (x += 1) {
            self.curr_page.getCell(x, y).clear(
                self.curr_page.curr_bg,
                self.curr_page.curr_fg
            );
        }
        self.curr_page.markDirty(DirtyRect.init(
            0,
            y,
            self.curr_page.cursor.x + 1,
            y
        ));
        self.render();
    }

    fn clearLine(self: *TTY) void {
        const y = self.curr_page.cursor.y;
        var x: usize = 0;
        while (x < self.width) : (x += 1) {
            self.curr_page.getCell(x, y).clear(
                self.curr_page.curr_bg,
                self.curr_page.curr_fg
            );
        }
        self.curr_page.markDirty(DirtyRect.init(
            0,
            y,
            self.width - 1,
            y
        ));
        self.render();
    }

    fn clearScreen(self: *TTY) void {
        self.curr_page.clearScreen();
    }

    fn clearFromCursorToEnd(self: *TTY) void {
        self.clearToEol();
        var row = self.curr_page.cursor.y + 1;
        while (row < self.height) : (row += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                self.curr_page.getCell(x, row).clear(
                    self.curr_page.curr_bg,
                    self.curr_page.curr_fg
                );
            }
        }
        self.curr_page.markDirty(DirtyRect.init(
            0,
            self.curr_page.cursor.y + 1,
            self.width - 1,
            self.height - 1
        ));
        self.render();
    }

    fn clearFromStartToCursor(self: *TTY) void {
        self.clearToBol();
        var row: usize = 0;
        while (row < self.curr_page.cursor.y) : (row += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                self.curr_page.getCell(x, row).clear(
                    self.curr_page.curr_bg,
                    self.curr_page.curr_fg
                );
            }
        }
        self.curr_page.markDirty(DirtyRect.init(
            0,
            0,
            self.width - 1,
            self.curr_page.cursor.y - 1
        ));
        self.render();
    }

    fn insertLines(self: *TTY, n: usize) void {
        const y = self.curr_page.cursor.y;
        const lines = @min(n, self.height - y);
        if (lines == 0)
            return;
        
        // Move lines down
        var row = self.height - 1;
        while (row >= y + lines) : (row -= 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                self.curr_page.getCell(x, row).* = self.curr_page.getCell(
                    x, row - lines
                ).*;
            }
            if (row == 0)
                break;
        }
        
        // Clear inserted lines
        var clear_row = y;
        while (clear_row < y + lines and clear_row < self.height) : (clear_row += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                self.curr_page.getCell(x, clear_row).clear(
                    self.curr_page.curr_bg,
                    self.curr_page.curr_fg
                );
            }
        }
        
        self.curr_page.markDirty(
            DirtyRect.init(0, y, self.width - 1, self.height - 1)
        );
        self.render();
    }

    fn deleteLines(self: *TTY, n: usize) void {
        const y = self.curr_page.cursor.y;
        const lines = @min(n, self.height - y);
        if (lines == 0) return;
        
        // Move lines up
        var row = y;
        while (row < self.height - lines) : (row += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                self.curr_page.getCell(x, row).* = self.curr_page.getCell(
                    x, row + lines
                ).*;
            }
        }
        
        // Clear bottom lines
        while (row < self.height) : (row += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                self.curr_page.getCell(x, row).clear(
                    self.curr_page.curr_bg,
                    self.curr_page.curr_fg
                );
            }
        }
        
        self.curr_page.markDirty(
            DirtyRect.init(0, y, self.width - 1, self.height - 1));
        self.render();
    }

    fn deleteChars(self: *TTY, n: usize) void {
        const x = self.curr_page.cursor.x;
        const y = self.curr_page.cursor.y;
        const chars = @min(n, self.width - x);
        if (chars == 0)
            return;
        
        // Shift characters left
        var col = x;
        while (col < self.width - chars) : (col += 1) {
            self.curr_page.getCell(col, y).* = self.curr_page.getCell(
                col + chars, y
            ).*;
        }
        
        // Clear end of line
        while (col < self.width) : (col += 1) {
            self.curr_page.getCell(col, y).clear(
                self.curr_page.curr_bg,
                self.curr_page.curr_fg
            );
        }
        
        self.curr_page.markDirty(
            DirtyRect.init(x, y, self.width - 1, y)
        );
        self.render();
    }

    fn insertChars(self: *TTY, n: usize) void {
        const x = self.curr_page.cursor.x;
        const y = self.curr_page.cursor.y;
        const chars = @min(n, self.width - x);
        if (chars == 0)
            return;
        
        // Shift characters right
        var col = self.width - 1;
        while (col >= x + chars) : (col -= 1) {
            self.curr_page.getCell(col, y).* = self.curr_page.getCell(col - chars, y).*;
            if (col == 0)
                break;
        }
        
        // Clear inserted space
        var clear_col = x;
        while (clear_col < x + chars and clear_col < self.width) : (clear_col += 1) {
            self.curr_page.getCell(clear_col, y).clear(
                self.curr_page.curr_bg,
                self.curr_page.curr_fg
            );
        }
        
        self.curr_page.markDirty(
            DirtyRect.init(x, y, self.width - 1, y)
        );
        self.render();
    }

    fn scrollDown(self: *TTY, n: usize) void {
        self.curr_page.scrollDown(n);
        self.render();
    }

    fn reportCursorPosition(self: *TTY) void {
        // Send cursor position: ESC [ row ; col R
        var buf: [20]u8 = undefined;
        const row = self.curr_page.cursor.y + 1;
        const col = self.curr_page.cursor.x + 1;

        const sl = std.fmt.bufPrint(
            buf[0..20],
            "\x1b[{d};{d}R",
            .{row, col}
        ) catch "\x1b[0;0R";
        self.pushSeq(sl);
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
                ']' => {
                    self.pstate = .Osc;
                },
                '(' , ')' => {
                    self.pstate = .Normal;
                },
                '7' => {
                    self.saveCursor();
                    self.pstate = .Normal;
                },
                '8' => {
                    self.restoreCursor();
                    self.pstate = .Normal;
                },
                'M' => {
                    // Reverse Index - move cursor up one line, scroll if needed
                    if (self.curr_page.cursor.y > 0) {
                        self.curr_page.setCursorY(self.curr_page.cursor.y - 1);
                    } else {
                        self.curr_page.scrollUp(1);
                    }
                    self.pstate = .Normal;
                },
                'D' => {
                    // Index - move cursor down one line, scroll if needed
                    if (self.curr_page.cursor.y < self.height - 1) {
                        self.curr_page.setCursorY(self.curr_page.cursor.y + 1);
                    } else {
                        self.curr_page.scrollDown(1);
                    }
                    self.pstate = .Normal;
                },
                'E' => {
                    // Next Line - move to start of next line
                    self.curr_page.wrapLine();
                    self.pstate = .Normal;
                },
                'c' => {
                    // RIS - Reset to Initial State
                    self.clear();
                    self.pstate = .Normal;
                },
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
                if (b == ';' or b == ':') {
                    self.csiNextParam();
                    return;
                }
                self.csiAct(b);
            },
            .Osc => {
                if (b >= '0' and b <= '9') {
                    return;
                }
                if (b == ';') {
                    self.pstate = .OscString;
                    return;
                }
                self.pstate = .Normal;
            },
            .OscString => {
                if (b == 0x07) {
                    self.pstate = .Normal;
                } else if (b == 0x1b) {
                    self.pstate = .Normal;
                }
            },
        }
    }
};
