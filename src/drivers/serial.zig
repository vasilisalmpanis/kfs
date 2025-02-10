const io = @import("arch").io;

pub const Serial = struct {
    addr: u16 = 0x3F8, // COM1
    pub fn init() Serial {
        const serial = Serial{};
        io.outb(serial.addr + 1, 0x00);
        io.outb(serial.addr + 3, 0x80);
        io.outb(serial.addr, 0x01);
        io.outb(serial.addr + 1, 0x00);
        io.outb(serial.addr + 3, 0x03);
        io.outb(serial.addr + 2, 0xC7);
        io.outb(serial.addr + 1, 0x01);
        return serial;
    }

    pub fn putchar(self: *Serial, char: u8) void {
        while ((io.inb(self.addr + 5) & 0x20) == 0) {}
        io.outb(self.addr, char);
    }

    pub fn print(self: *Serial, message: []const u8) void {
        for (message) |char| {
            self.putchar(char);
        }
    }
};
