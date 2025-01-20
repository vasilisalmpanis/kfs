const ascii = @import("std").ascii;
const io = @import("arch").io;

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

    pub fn get_input(self: *Keyboard) [2]u8 {
        const byte: u8 = io.inb(0x60);
        if (byte != self.last_scancode) {
            self.last_scancode = byte;
            self.key_pressed = true;
            switch (byte) {
                0x2A, 0x36 => self.shift = true,
                0x2A | 0x80, 0x36 | 0x80 => self.shift = false,
                0x1D => self.cntl = true,
                0x1D | 0x80 => self.cntl = false,
                0x38 => self.alt = true,
                0x38 | 0x80 => self.alt = false,
                0x3A => self.caps = !self.caps,
                0x4B => self.left = true,
                0x4B | 0x80 => self.left = false,
                0x4D => self.right = true,
                0x4D | 0x80 => self.right = false,
                else => {}
            }
            var char = scancode_to_char(byte);
            if (self.left) {
                self.left = false;
                return .{'M', 0};
            }
            if (self.right) {
                self.right = false;
                return .{'M', 1};
            }
            if (self.cntl and ascii.isDigit(char))
                return .{'T', char - '0'};
            if (self.cntl and char == 'L')
                return .{'C', 0};
            if (self.cntl and char == 'S')
                return .{'S', 0};
            if (self.cntl and char == 'R')
                return .{'R', 0};
            if (self.cntl and char == 'I')
                return .{'I', 0};
            if ((self.shift and self.caps) or (!self.shift and !self.caps))
                char = ascii.toLower(char);
            if (self.shift and (char < 'A' or char > 'Z'))
                char = getShiftedChar(char);
            return .{0, char};
        } else if (self.key_pressed) {
            self.key_pressed = false;
            self.last_scancode = byte;
        }
        return .{0, 0};
    }
};
