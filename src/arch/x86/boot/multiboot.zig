pub const MultibootInfo = packed struct {
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
    drives_length: u32,
    drives_addr: u32,
    config_table: u32,
    boot_loader_name: u32,
    apm_table: u32,
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
};

pub const MultibootMemoryMap = struct {
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

pub const FramebufferInfo = struct {
    address: u32,
    width: u32,
    height: u32,
    pitch: u32,
};

pub fn getFBInfo(multiboot_ptr: *const MultibootInfo) ?FramebufferInfo {
    // Check if framebuffer info is available (bit 12)
    const MULTIBOOT_FRAMEBUFFER_INFO = (1 << 12);
    if ((multiboot_ptr.flags & MULTIBOOT_FRAMEBUFFER_INFO) == 0) {
        return null;
    }

    return FramebufferInfo{
        .address = @truncate(multiboot_ptr.framebuffer_addr),
        .width = multiboot_ptr.framebuffer_width,
        .height = multiboot_ptr.framebuffer_height,
        .pitch = multiboot_ptr.framebuffer_pitch,
    };
}
