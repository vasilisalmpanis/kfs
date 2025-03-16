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

pub fn halt() noreturn {
    asm volatile (\\
        \\ cli
        \\ hlt
        \\ loop:
        \\   jmp loop
    );
    while(true) {}
}

pub fn shutdown() noreturn {
    _ = io.outw(0x604, 0x2000);
    while (true) {}
}

pub fn enableWriteProtect() void {
    // Set the WP bit (bit 16) in CR0
    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x10000, %%eax    # Set WP bit (bit 16)
        \\mov %%eax, %%cr0
        ::: "eax", "memory"
    );
}

pub fn disableWriteProtect() void {
    // Clear the WP bit (bit 16) in CR0
    asm volatile (
        \\mov %%cr0, %%eax
        \\and $0xFFFEFFFF, %%eax    # Clear WP bit (bit 16)
        \\mov %%eax, %%cr0
        ::: "eax", "memory"
    );
}

