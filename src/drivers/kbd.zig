const io = @import("arch").io;
const std = @import("std");
const krn = @import("kernel");
pub const keymap_us = @import("./keymaps.zig").keymap_us;
pub const keymap_de = @import("./keymaps.zig").keymap_de;

pub const ScanCode = enum(u8) {
    K_ESC = 0x1,
    // Main block    
    K_1, K_2, K_3, K_4, K_5, K_6, K_7, K_8, K_9, K_0, K_MINUS, K_EQUALS, K_BACKSPACE,
    K_TAB, K_Q, K_W, K_E, K_R, K_T, K_Y, K_U, K_I, K_O, K_P, K_OSQB, K_CSQB, K_ENTER,
    K_LCTRL, K_A, K_S, K_D, K_F, K_G, K_H, K_J, K_K, K_L, K_SEMICOL, K_QUOTE, K_BCKQUOTE,
    K_LSHIFT, K_BCKSL, K_Z, K_X, K_C, K_V, K_B, K_N, K_M, K_COMMA, K_DOT, K_SLASH, K_RSHIFT,
    
    K_KPAD_STAR, K_LALT, K_WHITESPACE, K_CAPSLOCK,
    // Function keys
    K_F1, K_F2, K_F3, K_F4, K_F5, K_F6, K_F7, K_F8, K_F9, K_F10,
    // Keypad
    K_NUMLOCK, K_SCRLLOCK,
    K_HOME, K_UP, K_PGUP, K_KPAD_MINUS,
    K_LEFT, K_KPAD_FIVE, K_RIGHT, K_KPAD_PLUS,
    K_END, K_DOWN, K_PGDN,
    K_INS, K_DEL,
    // Additional keys
    K_ALT_SYSRQ = 0x54,
    K_FN = 0x55,
    K_LLALT = 0x56,
    K_F11 = 0x57,
    K_F12 = 0x58,

    K_LMODAL = 0x5b,
    K_RMODAL = 0x5c,
    K_MENU = 0x5d,
    K_POWER = 0x5e,
    K_SLEEP = 0x5f,

    K_WAKE = 0x63,
    _,
};

pub const KeymapEntry = struct {
    normal: u8,
    shift: ?u8 = null,
    ctrl: ?u8 = null,
    alt: ?u8 = null,
};

pub const KeyEvent = struct {
    ctl: bool,
    val: u8,
};

pub const CtrlType = enum(u8) {
    LEFT,
    RIGHT,
    UP,
    DOWN,
    HOME,
    END,
    TTY1,
    TTY2,
    TTY3,
    TTY4,
    TTY5,
    TTY6,
    TTY7,
    TTY8,
    TTY9,
    TTY10,
    _
};

var input: [256]KeyEvent = undefined;

pub const Keyboard = struct {
    write_pos: u8 = 0,
    read_pos: u8 = 0,
    buffer: [256]u8,
    keymap: *const std.EnumMap(ScanCode, KeymapEntry),

    shift: bool,
    cntl: bool,
    alt: bool,
    caps: bool,

    pub fn init(keymap: *const std.EnumMap(ScanCode, KeymapEntry)) Keyboard {
        return Keyboard{
            .buffer = .{0} ** 256,
            .keymap = keymap,
            .shift = false,
            .cntl = false,
            .alt = false,
            .caps = false,
        };
    }

    pub fn setKeymap(
        self: *Keyboard,
        keymap: *const std.EnumMap(ScanCode, KeymapEntry)
    ) void {
        self.keymap = keymap;
    }

    inline fn kbWait() void {
        for (0..0x10000) |_| {
            if (io.inb(0x64) & 0x02 == 0)
                break;
        }
    }

    pub export fn sendCommand(_: *Keyboard, cmd: u8) void {
        kbWait();
        io.outb(0x64, cmd);
    }

    pub export fn saveScancode(self: *Keyboard, scancode: u8) void {
        self.buffer[self.write_pos] = scancode;
        if (self.write_pos == 255) {
            self.write_pos = 0;
        } else {
            self.write_pos += 1;
        }
        if (self.buffer[self.write_pos] != 0) {
            self.read_pos = self.write_pos;
        }
    }

    fn getScancode(self: *Keyboard) u8 {
        const scancode = self.buffer[self.read_pos];
        if (scancode == 0)
            return 0;
        self.buffer[self.read_pos] = 0;
        if (self.read_pos == 255) {
            self.read_pos = 0;
        } else {
            self.read_pos += 1;
        }
        return scancode;
    }

    fn getKeyevent(self: *Keyboard, scancode: u8) ?KeyEvent {
        const release_mask: u8 = 0x80;
        var code = scancode;
        var release: bool = false;
        if (code & release_mask == release_mask) {
            release = true;
            code = code & (~release_mask);
        }
        const enumcode: ScanCode = @enumFromInt(code);
        switch (enumcode) {
            .K_LALT                 => { self.alt = if (release) false else true; },
            .K_LCTRL                => { self.cntl = if (release) false else true; },
            .K_LSHIFT, .K_RSHIFT    => { self.shift = if (release) false else true; },
            .K_CAPSLOCK             => { self.caps = if (release) self.caps else !self.caps; },
            .K_LEFT                 => {if (!release) return .{ .ctl = true, .val = @intFromEnum(CtrlType.LEFT) }; },
            .K_RIGHT                => {if (!release) return .{ .ctl = true, .val = @intFromEnum(CtrlType.RIGHT) }; },
            .K_UP                   => {if (!release) return .{ .ctl = true, .val = @intFromEnum(CtrlType.UP) }; },
            .K_DOWN                 => {if (!release) return .{ .ctl = true, .val = @intFromEnum(CtrlType.DOWN) }; },
            .K_HOME                 => {if (!release) return .{ .ctl = true, .val = @intFromEnum(CtrlType.HOME) }; },
            .K_END                  => {if (!release) return .{ .ctl = true, .val = @intFromEnum(CtrlType.END) }; },
            .K_F1,.K_F2,.K_F3,
            .K_F4,.K_F5,.K_F6,
            .K_F7,.K_F8,.K_F9,.K_F10 => {
                if (!release and self.cntl) {
                    return .{
                        .ctl = true,
                        .val = @intFromEnum(enumcode) - @intFromEnum(ScanCode.K_F1) + @intFromEnum(CtrlType.TTY1)
                    };
                }
            },
            else => {
                if (release)
                    return null;
                const shiftstate: bool = (self.shift != self.caps);
                const entry = self.keymap.get(enumcode);
                if (entry == null) {
                    krn.logger.INFO(
                        "Unknown scancode: {x} {any}\n",
                        .{code, enumcode}
                    );
                    return null;
                }
                if (self.alt and entry.?.alt != null)
                    return .{ .ctl = false, .val = entry.?.alt.? };
                if (self.cntl and entry.?.ctrl != null)
                    return .{ .ctl = false, .val = entry.?.ctrl.? };
                if (shiftstate and entry.?.shift != null
                        and std.ascii.isAlphabetic(entry.?.normal))
                    return .{ .ctl = false, .val = entry.?.shift.? };
                if (self.shift and entry.?.shift != null
                        and !std.ascii.isAlphabetic(entry.?.normal))
                    return .{ .ctl = false, .val = entry.?.shift.? };
                return .{ .ctl = false, .val = entry.?.normal};
            }
        }
        return null;
    }

    pub fn getInput(self: *Keyboard) ?[] const KeyEvent {
        self.sendCommand(0xAD); // Disable keyboard
        defer self.sendCommand(0xAE); // Enable keyboard
        var scancode = self.getScancode();
        if (scancode == 0)
            return null;
        var pos: u8 = 0;
        while (scancode != 0 and pos < 256) {
            if (self.getKeyevent(scancode)) |key_event| {
                // krn.logger.DEBUG("event: {}\n", .{key_event});
                input[pos] = key_event;
                pos += 1;
            }
            scancode = self.getScancode();
        }
        if (pos == 0)
            return null;
        return input[0..pos];
    }
};

pub var keyboard = Keyboard.init(&keymap_us);
pub var global_keyboard = &keyboard;

pub fn keyboardInterrupt() void {
    var scancode: u8 = undefined;
    keyboard.sendCommand(0xAD); // Disable keyboard
    defer keyboard.sendCommand(0xAE); // Enable keyboard
    if (io.inb(0x64) & 0x01 != 0x01)
        return ;
    scancode = io.inb(0x60);
    switch (scancode) {
        0xfa, 0xfe  => return,
        0           => { return; },
        0xff        => { return; },
        else        => {}
    }
    // handle e0 e1
    keyboard.saveScancode(scancode);
}

pub fn init() void {
    global_keyboard = &keyboard;
    krn.irq.registerHandler(1, &keyboardInterrupt);
}
