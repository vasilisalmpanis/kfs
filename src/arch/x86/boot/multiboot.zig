pub const multiboot_info = packed struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms_0: u32,
    syms_1: u32,
    syms_2: u32,
    syms_3: u32,
    mmap_length: u32,
    mmap_addr: u32,
};

pub const multiboot_memory_map = struct {
    size: u32,
    addr: [2]u32,
    len: [2]u32,
    type: u32,
};

