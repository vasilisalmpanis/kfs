const io = @import("arch").io;
const std = @import("std");
const krn = @import("kernel");
const keymap_us = @import("./keymaps.zig").keymap_us;


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
    _,
};

pub const KeymapEntry = struct {
    normal: u8,
    shift: ?u8 = null,
    ctrl: ?u8 = null,
    alt: ?u8 = null,
};

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

    inline fn kb_wait() void {
        for (0..0x10000) |_| {
            if (io.inb(0x64) & 0x02 == 0)
                break;
        }
    }

    fn send_command(_: *Keyboard, cmd: u8) void {
        kb_wait();
        io.outb(0x64, cmd);
    }

    fn save_scancode(self: *Keyboard, scancode: u8) void {
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

    fn get_scancode(self: *Keyboard) u8 {
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

    fn get_ascii(self: *Keyboard, scancode: u8) u8 {
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
            else => {
                if (release)
                    return 0;
                const shiftstate: bool = (self.shift != self.caps);
                const entry = self.keymap.get(enumcode);
                if (entry == null) {
                    krn.logger.INFO(
                        "Unknown scancode: {x} {any}\n",
                        .{code, enumcode}
                    );
                    return 0;
                }
                if (self.alt and entry.?.alt != null)
                    return entry.?.alt.?;
                if (self.cntl and entry.?.ctrl != null)
                    return entry.?.ctrl.?;
                if (shiftstate and entry.?.shift != null
                        and std.ascii.isAlphabetic(entry.?.normal))
                    return entry.?.shift.?;
                if (self.shift and entry.?.shift != null
                        and !std.ascii.isAlphabetic(entry.?.normal))
                    return entry.?.shift.?;
                return entry.?.normal;
            }
        }
        return 0;
    }

    pub fn get_input(self: *Keyboard) [] const u8 {
        var scancode = self.get_scancode();
        if (scancode == 0)
            return "";
        var input: [256]u8 = .{0} ** 256;
        var pos: u8 = 0;
        var ascii_ch: u8 = 0;
        while (scancode != 0) {
            ascii_ch = self.get_ascii(scancode);
            if (ascii_ch != 0) {
                input[pos] = ascii_ch;
                pos += 1;
            }
            scancode = self.get_scancode();
        }
        return input[0..pos];
    }
};

pub var keyboard = Keyboard.init(&keymap_us);

pub fn keyboard_interrupt() void {
    var scancode: u8 = undefined;
    keyboard.send_command(0xAD); // Disable keyboard
    defer keyboard.send_command(0xAE); // Enable keyboard
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
    keyboard.save_scancode(scancode);
}
