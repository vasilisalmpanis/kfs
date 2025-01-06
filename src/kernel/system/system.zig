const io = @import("../io.zig");
pub fn reboot() noreturn {
    var temp : u8 = io.inb(0x64);

    asm volatile ("cli"); // disable interrupts

    while ((temp & (1 << 1)) != 0) {
        temp = io.inb(0x64); // empty user data
        if ((temp & (1 << 0)) != 0) {
            _ = io.inb(0x60); // empty keyboard data
        }
    }
    _ = io.outb(0x64, 0xFE); // CPU reset
    while (true) {
        asm volatile ("hlt");
        // in case of non maskable interrupts
        // halt again.
    }
}

