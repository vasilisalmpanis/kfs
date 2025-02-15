const ascii = @import("std").ascii;
const io = @import("arch").io;
const std = @import("std");
const krn = @import("kernel");

const ScanCode = enum(u8) {
    K_NONE = 0x0,
    K_ESC = 0x1,
    K_ONE, K_TWO, K_THREE, K_FOUR, K_FIVE, K_SIX, K_SEVEN, K_EIGHT, K_NINE, K_ZERO, K_MINUS, K_EQUALS, K_BACKSPACE,
    K_TAB, K_Q, K_W, K_E, K_R, K_T, K_Y, K_U, K_I, K_O, K_P, K_OSQB, K_CSQB, K_ENTER,
    K_LCTRL, K_A, K_S, K_D, K_F, K_G, K_H, K_J, K_K, K_L, K_SEMICOL, K_QUOTE, K_BCKQUOTE,
    K_LSHIFT, K_BCKSL, K_Z, K_X, K_C, K_V, K_B, K_N, K_M, K_COMMA, K_DOT, K_SLASH, K_RSHIFT,
    K_KPAD_STAR, K_LALT, K_WHITESPACE, K_CAPSLOCK,
    K_F1, K_F2, K_F3, K_F4, K_F5, K_F6, K_F7, K_F8, K_F9, K_F10, K_NUMLOCK, K_SCRLLOCK,
    K_HOME, K_UP, K_PGUP, K_KPAD_MINUS, K_LEFT, K_KPAD_FIVE, K_RIGHT, K_KPAD_PLUS, K_END, K_DOWN, K_PGDN, K_INS, K_DEL,
    K_ALT_SYSRQ = 0x54,
    K_F11 = 0x57,
    K_F12 = 0x58,
    _,
};

const KeymapEntry = struct {
    normal: u8,
    shift: ?u8 = null,
    ctrl: ?u8 = null,
    alt: ?u8 = null,
};

const keymap = std.EnumMap(
    ScanCode,
    KeymapEntry
).init(.{
    .K_ESC          = .{ .normal = 27, },
    .K_ONE          = .{ .normal = '1', .shift = '!', },
    .K_TWO          = .{ .normal = '2', .shift = '@', },
    .K_THREE        = .{ .normal = '3', .shift = '#', },
    .K_FOUR         = .{ .normal = '4', .shift = '$', },
    .K_FIVE         = .{ .normal = '5', .shift = '%', },
    .K_SIX          = .{ .normal = '6', .shift = '^', },
    .K_SEVEN        = .{ .normal = '7', .shift = '&', },
    .K_EIGHT        = .{ .normal = '8', .shift = '*', },
    .K_NINE         = .{ .normal = '9', .shift = '(', },
    .K_ZERO         = .{ .normal = '0', .shift = ')', },
    .K_MINUS        = .{ .normal = '-', .shift = '_', },
    .K_EQUALS       = .{ .normal = '=', .shift = '+', },
    .K_BACKSPACE    = .{ .normal = 8, },
    .K_TAB          = .{ .normal = '\t', },
    .K_Q            = .{ .normal = 'q', .shift = 'Q', }, 
    .K_W            = .{ .normal = 'w', .shift = 'W', }, 
    .K_E            = .{ .normal = 'e', .shift = 'E', }, 
    .K_R            = .{ .normal = 'r', .shift = 'R', }, 
    .K_T            = .{ .normal = 't', .shift = 'T', }, 
    .K_Y            = .{ .normal = 'y', .shift = 'Y', }, 
    .K_U            = .{ .normal = 'u', .shift = 'U', }, 
    .K_I            = .{ .normal = 'i', .shift = 'I', }, 
    .K_O            = .{ .normal = 'o', .shift = 'O', }, 
    .K_P            = .{ .normal = 'p', .shift = 'P', },
    .K_OSQB         = .{ .normal = '[', .shift = '{' }, 
    .K_CSQB         = .{ .normal = ']', .shift = '}' }, 
    .K_ENTER        = .{ .normal = '\n', },

    .K_A            = .{ .normal = 'a', .shift = 'A', },
    .K_S            = .{ .normal = 's', .shift = 'S', },
    .K_D            = .{ .normal = 'd', .shift = 'D', },
    .K_F            = .{ .normal = 'f', .shift = 'F', },
    .K_G            = .{ .normal = 'g', .shift = 'G', },
    .K_H            = .{ .normal = 'h', .shift = 'H', },
    .K_J            = .{ .normal = 'j', .shift = 'J', },
    .K_K            = .{ .normal = 'k', .shift = 'K', },
    .K_L            = .{ .normal = 'l', .shift = 'L', },
    .K_SEMICOL      = .{ .normal = ';', .shift = ':', },
    .K_QUOTE        = .{ .normal = '\'', .shift = '"', },
    .K_BCKQUOTE     = .{ .normal = '`', .shift = '~', },

    
    .K_BCKSL        = .{ .normal = '\\', .shift = '|', }, 
    .K_Z            = .{ .normal = 'z', .shift = 'Z', }, 
    .K_X            = .{ .normal = 'x', .shift = 'X', }, 
    .K_C            = .{ .normal = 'c', .shift = 'C', }, 
    .K_V            = .{ .normal = 'v', .shift = 'V', }, 
    .K_B            = .{ .normal = 'b', .shift = 'B', }, 
    .K_N            = .{ .normal = 'n', .shift = 'N', }, 
    .K_M            = .{ .normal = 'm', .shift = 'M', }, 
    .K_COMMA        = .{ .normal = ',', .shift = '<', }, 
    .K_DOT          = .{ .normal = '.', .shift = '>', }, 
    .K_SLASH        = .{ .normal = '/', .shift = '?', },

    .K_WHITESPACE   = .{ .normal = ' ', }
});

pub fn scancode_to_char(scancode: u8) u8 {
    const a: u8 = switch (scancode) {
        0x01 => 27, // Esc
        0x02 => '1',
        0x03 => '2',
        0x04 => '3',
        0x05 => '4',
        0x06 => '5',
        0x07 => '6',
        0x08 => '7',
        0x09 => '8',
        0x0A => '9',
        0x0B => '0',
        0x0C => '-',
        0x0D => '=',
        0x0E => 8, // Backspace
        0x0F => '\t',
        0x10 => 'Q',
        0x11 => 'W',
        0x12 => 'E',
        0x13 => 'R',
        0x14 => 'T',
        0x15 => 'Y',
        0x16 => 'U',
        0x17 => 'I',
        0x18 => 'O',
        0x19 => 'P',
        0x1A => '[',
        0x1B => ']',
        0x1C => '\n',
        0x1D => 0, //"Left Control",
        0x1E => 'A',
        0x1F => 'S',
        0x20 => 'D',
        0x21 => 'F',
        0x22 => 'G',
        0x23 => 'H',
        0x24 => 'J',
        0x25 => 'K',
        0x26 => 'L',
        0x27 => ';',
        0x28 => '\'',
        0x29 => '`',
        0x2A => 0, //"Left Shift",
        0x2B => '\\',
        0x2C => 'Z',
        0x2D => 'X',
        0x2E => 'C',
        0x2F => 'V',
        0x30 => 'B',
        0x31 => 'N',
        0x32 => 'M',
        0x33 => ',',
        0x34 => '.',
        0x35 => '/',
        0x36 => 0, //"Right Shift",
        0x37 => 0, //"Keypad *",
        0x38 => 0, //"Left Alt",
        0x39 => ' ',
        0x3A => 0, //"Caps Lock",
        0x3B => 0, //"F1",
        0x3C => 0, //"F2",
        0x3D => 0, //"F3",
        0x3E => 0, //"F4",
        0x3F => 0, //"F5",
        0x40 => 0, //"F6",
        0x41 => 0, //"F7",
        0x42 => 0, //"F8",
        0x43 => 0, //"F9",
        0x44 => 0, //"F10",
        0x45 => 0, //"Num Lock",
        0x46 => 0, //"Scroll Lock",
        0x4b => 0, // Left
        0x4d => 0, // Right
        else => 0, //"",
    };
    return a;
}

pub fn getShiftedChar(unshifted: u8) u8 {
    return switch (unshifted) {
        // Numbers and symbols
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '0' => ')',
        '-' => '_',
        '=' => '+',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        ';' => ':',
        '\'' => '"',
        ',' => '<',
        '.' => '>',
        '/' => '?',
        '`' => '~',

        // Letters are not changed
        'a'...'z', 'A'...'Z' => unshifted,

        // Default case (no shifted character)
        else => unshifted,
    };
}

pub const Keyboard = struct {
    write_pos: u8 = 0,
    read_pos: u8 = 0,
    buffer: [256]u8,

    last_scancode: u8,
    key_pressed: bool,
    shift: bool,
    cntl: bool,
    alt: bool,
    caps: bool,
    left: bool,
    right: bool,

    pub fn init() Keyboard {
        return Keyboard{
            .buffer = .{0} ** 256,
            .last_scancode = 0,
            .key_pressed = false,
            .shift = false,
            .cntl = false,
            .alt = false,
            .caps = false,
            .left = false,
            .right = false,
        };
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
            .K_LALT => { self.alt = if (release) false else true; },
            .K_LCTRL => { self.cntl = if (release) false else true; },
            .K_LSHIFT => { self.shift = if (release) false else true; },
            .K_CAPSLOCK => { self.caps = if (release) self.caps else !self.caps; },
            else => {
                if (release)
                    return 0;
                const shiftstate: bool = (self.shift != self.caps);
                const entry = keymap.get(@enumFromInt(code));
                if (entry == null)
                    return 0;
                if (self.alt and entry.?.alt != null)
                    return entry.?.alt.?;
                if (self.cntl and entry.?.ctrl != null)
                    return entry.?.ctrl.?;
                if (shiftstate and entry.?.shift != null and entry.?.normal >= 'a' and entry.?.normal <= 'z')
                    return entry.?.shift.?;
                if (self.shift and entry.?.shift != null)
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

        // const byte: u8 = io.inb(0x60);
        // if (byte != self.last_scancode) {
        //     self.last_scancode = byte;
        //     self.key_pressed = true;
        //     switch (byte) {
        //         0x2A, 0x36 => self.shift = true,
        //         0x2A | 0x80, 0x36 | 0x80 => self.shift = false,
        //         0x1D => self.cntl = true,
        //         0x1D | 0x80 => self.cntl = false,
        //         0x38 => self.alt = true,
        //         0x38 | 0x80 => self.alt = false,
        //         0x3A => self.caps = !self.caps,
        //         0x4B => self.left = true,
        //         0x4B | 0x80 => self.left = false,
        //         0x4D => self.right = true,
        //         0x4D | 0x80 => self.right = false,
        //         else => {}
        //     }
        //     var char = scancode_to_char(byte);
        //     if (self.left) {
        //         self.left = false;
        //         return .{'M', 0};
        //     }
        //     if (self.right) {
        //         self.right = false;
        //         return .{'M', 1};
        //     }
        //     if (self.cntl and ascii_ch.isDigit(char))
        //         return .{'T', char - '0'};
        //     if (self.cntl and char == 'L')
        //         return .{'C', 0};
        //     if (self.cntl and char == 'S')
        //         return .{'S', 0};
        //     if (self.cntl and char == 'R')
        //         return .{'R', 0};
        //     if (self.cntl and char == 'I')
        //         return .{'I', 0};
        //     if (self.cntl and char == 'D')
        //         return .{'D', 0};
        //     if ((self.shift and self.caps) or (!self.shift and !self.caps))
        //         char = ascii_ch.toLower(char);
        //     if (self.shift and (char < 'A' or char > 'Z'))
        //         char = getShiftedChar(char);
        //     return .{0, char};
        // } else if (self.key_pressed) {
        //     self.key_pressed = false;
        //     self.last_scancode = byte;
        // }
        // return .{0, 0};
    }
};

pub var keyboard = Keyboard.init();

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
