pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub fn scancode_to_key(scancode: u8) []const u8 {
    const a = switch (scancode) {
        0x01 => "Escape",
        0x02 => "1",
        0x03 => "2",
        0x04 => "3",
        0x05 => "4",
        0x06 => "5",
        0x07 => "6",
        0x08 => "7",
        0x09 => "8",
        0x0A => "9",
        0x0B => "0",
        0x0C => "Minus (-)",
        0x0D => "Equals (=)",
        0x0E => "Backspace",
        0x0F => "Tab",
        0x10 => "Q",
        0x11 => "W",
        0x12 => "E",
        0x13 => "R",
        0x14 => "T",
        0x15 => "Y",
        0x16 => "U",
        0x17 => "I",
        0x18 => "O",
        0x19 => "P",
        0x1A => "Left Bracket ([)",
        0x1B => "Right Bracket (])",
        0x1C => "Enter",
        0x1D => "Left Control",
        0x1E => "A",
        0x1F => "S",
        0x20 => "D",
        0x21 => "F",
        0x22 => "G",
        0x23 => "H",
        0x24 => "J",
        0x25 => "K",
        0x26 => "L",
        0x27 => "Semicolon (;)",
        0x28 => "Apostrophe (')",
        0x29 => "Grave (`)",
        0x2A => "Left Shift",
        0x2B => "Backslash (\\)",
        0x2C => "Z",
        0x2D => "X",
        0x2E => "C",
        0x2F => "V",
        0x30 => "B",
        0x31 => "N",
        0x32 => "M",
        0x33 => "Comma (,)",
        0x34 => "Period (.)",
        0x35 => "Slash (/)",
        0x36 => "Right Shift",
        0x37 => "Keypad *",
        0x38 => "Left Alt",
        0x39 => "Space",
        0x3A => "Caps Lock",
        0x3B => "F1",
        0x3C => "F2",
        0x3D => "F3",
        0x3E => "F4",
        0x3F => "F5",
        0x40 => "F6",
        0x41 => "F7",
        0x42 => "F8",
        0x43 => "F9",
        0x44 => "F10",
        0x45 => "Num Lock",
        0x46 => "Scroll Lock",
        else => "",
    };
    return a;
}
