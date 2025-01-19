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
    size: u32,      // Size of the memory_map struct
    addr: [2]u32,   // Base address
    len: [2]u32,    // Length in bytes
    //MULTIBOOT_MEMORY_AVAILABLE              1
    //MULTIBOOT_MEMORY_RESERVED               2
    //MULTIBOOT_MEMORY_ACPI_RECLAIMABLE       3
    //MULTIBOOT_MEMORY_NVS                    4
    //MULTIBOOT_MEMORY_BADRAM                 5
    type: u32,
};

