/// Transfers a byte from a
/// port (0 to 65535), specified in the DX register, into the byte
/// memory address pointed to by the AL register
pub export fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

/// Transfers a word from a
/// port (0 to 65535), specified in the DX register, into the word
/// memory address pointed to by the AX register
pub export fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

/// Transfers a long from a
/// port (0 to 65535), specified in the DX register, into the byte
/// memory address pointed to by the EAX register
pub export fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "N{dx}" (port),
    );
}

/// Transfers a byte from the AL register
/// to a port (0 to 65535), specified by
/// the DX register.
pub export fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

/// Transfers a word from the AX register
/// to a port (0 to 65535), specified by
/// the DX register.
pub export fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "N{dx}" (port),
    );
}

/// Transfers a long from the EAX register
/// to a port (0 to 65535), specified by
/// the DX register.
pub export fn outl(port: u16, value: u32) void {
    return asm volatile ("outl %[value], %[port]"
        :
        : [value] "{eax}" (value),
          [port] "N{dx}" (port),
    );
}
