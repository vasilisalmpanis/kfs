const std = @import("std");

pub const MultibootInfo1 = packed struct {
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

pub const Multibo2otMemoryMap1 = struct {
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

pub const FramebufferInfo1 = struct {
    address: u32,
    width: u32,
    height: u32,
    pitch: u32,
};

pub fn getFBInfo1(multiboot_ptr: *const MultibootInfo1) ?FramebufferInfo1 {
    // Check if framebuffer info is available (bit 12)
    const MULTIBOOT_FRAMEBUFFER_INFO = (1 << 12);
    if ((multiboot_ptr.flags & MULTIBOOT_FRAMEBUFFER_INFO) == 0) {
        return null;
    }

    return FramebufferInfo1{
        .address = @truncate(multiboot_ptr.framebuffer_addr),
        .width = multiboot_ptr.framebuffer_width,
        .height = multiboot_ptr.framebuffer_height,
        .pitch = multiboot_ptr.framebuffer_pitch,
    };
}

pub const Header = struct {
    total_size: u32, 
    reserved: u32,
};

pub const Tag = struct {
    type: u32, 
    size: u32,
};

pub const TagBootCommandLine = struct {
    type: u32 = 1,
    size: u32,
};

pub const TagBootLoaderName = struct {
    type: u32 = 2,
    size: u32,
};

pub const TagModules = struct{
    type: u32 = 3,
    size: u32,
    start: u32,
    end: u32,
};

pub const TagBasicMemInfo = struct{
    type: u32 = 4,
    size: u32,
    mem_lower: u32,
    mem_upper: u32,
};

pub const TagBIOSBootDevice = struct{
    type: u32 = 5,
    size: u32,
    biosdev: u32,
    partition: u32,
    sub_partition: u32,
};

pub const MemMapEntry = struct {
    base_addr: u64,
    length: u64,
    type: u32,
    reserved: u32,
};

pub const TagMemoryMap = struct{
    type: u32 = 6,
    size: u32,
    entry_size: u32,
    entry_version: u32,

    pub fn getMemMapEntries(self: *TagMemoryMap) [*]MemMapEntry {
        const addr: u32 = @intFromPtr(self) + @sizeOf(TagMemoryMap);
        return @ptrFromInt(addr);
    }
};

pub const TagVBEInfo = struct{
    type: u32 = 7,
    size: u32,
    mode: u16,
    interface_seg: u16,
    interface_off: u16,
    interface_len: u16,
    control_info: [512]u8,
    mode_info: [256]u8,
};

pub const ColorInfo = extern union{
    rgb: extern struct{
        red_field_position: u8,
        red_mask_size: u8,
        green_field_position: u8,
        green_mask_size: u8,
        blue_field_position: u8,
        blue_mask_size: u8,
    },
    indexed: extern struct {
        num_colors: u16,
    },
};


pub const TagFrameBufferInfo = struct{
    type: u32 = 8,
    size: u32,
    addr: u64,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    fb_type: u8,
    reserved: u8,

    pub fn getColorInfo(self: *TagFrameBufferInfo) *ColorInfo {
        const addr: u32 = @intFromPtr(self) + @sizeOf(TagFrameBufferInfo);
        return @ptrFromInt(addr);
    }
};

pub const TagELFSymbols = struct{
    type: u32 = 9,
    size: u32,
    num: u16,
    entsize: u16,
    shndx: u16,
    reserved: u16,

    pub fn getSectionHeaders(self: *TagELFSymbols) [*]std.elf.Elf32_Shdr {
        const shdrs_size: u32 = @sizeOf(std.elf.Elf32_Shdr) * self.num;
        const padding: u32 = self.size - @sizeOf(TagELFSymbols) - shdrs_size;
        const addr: u32 = @intFromPtr(self) + @sizeOf(TagELFSymbols) + padding;
        return @ptrFromInt(addr);
    }
};

pub const TagAPMTable = struct{
    type: u32 = 10,
    size: u32,
    version: u16,
    cseg: u16,
    offset: u32,
    cseg_16: u16,
    dseg: u16,
    flags: u16,
    cseg_len: u16,
    cseg_16_len: u16,
    dseg_len: u16,
};

pub const TagEFI32SysTablePointer = struct{
    type: u32 = 11,
    size: u32,
    pointer: u32,
};

pub const TagEFI64SysTablePointer = struct{
    type: u32 = 12,
    size: u32,
    pointer: u64,
};

pub const TagSMBIOSTables = struct{
    type: u32 = 13,
    size: u32,
    major: u8,
    minor: u8,
    reserved: [6]u8,
};

pub const TagACPIOldRSDP = struct{
    type: u32 = 14,
    size: u32,
};

pub const TagACPINewRSDP = struct{
    type: u32 = 15,
    size: u32,
};

pub const TagNetInfo = struct{
    type: u32 = 16,
    size: u32,
};

pub const TagEFIMemMap = struct{
    type: u32 = 17,
    size: u32,
    descriptor_size: u32,
    descriptor_version: u32,
};

pub const TagEFIBootNotTerm = struct{
    type: u32 = 18,
    size: u32,
};

pub const TagEFI32HandlePtr = struct{
    type: u32 = 19,
    size: u32,
    pointer: u32,
};

pub const TagEFI64HandlePtr = struct{
    type: u32 = 20,
    size: u32,
    pointer: u64,
};

pub const TagImageLoadBasePhysAddr = struct{
    type: u32 = 21,
    size: u32,
    load_base_addr: u32,
};

pub const Multiboot = struct {
    addr: u32,
    header: *Header,
    curr_tag: ?*Tag = null,
    tag_addresses: [22]u32 = .{0} ** 22,
    
    pub fn init(addr: u32) Multiboot {
        var mtb = Multiboot{
            .addr = addr,
            .header = @ptrFromInt(addr),
        };
        while (mtb.nextTag()) |tag| {
            mtb.tag_addresses[tag.type] = @intFromPtr(tag);
        }
        return mtb;
    }

    pub fn nextTag(self: *Multiboot) ?*Tag {
        if (self.curr_tag) |tag| {
            const tag_addr: u32 = @intFromPtr(tag);
            var size = tag.size;
            if (size % 8 != 0) {
                size += (8 - size % 8);
            }
            if (tag_addr + size >= self.addr + self.header.total_size) {
                self.curr_tag = null;
            } else {
                self.curr_tag = @ptrFromInt(tag_addr + size);
            }
        } else {
            self.curr_tag = @ptrFromInt(self.addr + @sizeOf(Header));
        }
        return self.curr_tag;
    }

    pub fn getTag(self: *Multiboot, comptime T: type) ?*T {
        switch (T) {
            TagBootCommandLine => return
                if (self.tag_addresses[1] != 0)
                    @as(*TagBootCommandLine, @ptrFromInt(self.tag_addresses[1])) else null,
            TagBootLoaderName => return
                if (self.tag_addresses[2] != 0)
                    @as(*TagBootLoaderName, @ptrFromInt(self.tag_addresses[2])) else null,
            TagModules => return
                if (self.tag_addresses[3] != 0)
                    @as(*TagModules, @ptrFromInt(self.tag_addresses[3])) else null,
            TagBasicMemInfo => return
                if (self.tag_addresses[4] != 0)
                    @as(*TagBasicMemInfo, @ptrFromInt(self.tag_addresses[4])) else null,
            TagBIOSBootDevice => return
                if (self.tag_addresses[5] != 0)
                    @as(*TagBIOSBootDevice, @ptrFromInt(self.tag_addresses[5])) else null,
            TagMemoryMap => return
                if (self.tag_addresses[6] != 0)
                    @as(*TagMemoryMap, @ptrFromInt(self.tag_addresses[6])) else null,
            TagVBEInfo => return
                if (self.tag_addresses[7] != 0)
                    @as(*TagVBEInfo, @ptrFromInt(self.tag_addresses[7])) else null,
            TagFrameBufferInfo => return
                if (self.tag_addresses[8] != 0)
                    @as(*TagFrameBufferInfo, @ptrFromInt(self.tag_addresses[8])) else null,
            TagELFSymbols => return
                if (self.tag_addresses[9] != 0)
                    @as(*TagELFSymbols, @ptrFromInt(self.tag_addresses[9])) else null,
            TagAPMTable => return
                if (self.tag_addresses[10] != 0)
                    @as(*TagAPMTable, @ptrFromInt(self.tag_addresses[10])) else null,
            TagEFI32SysTablePointer => return
                if (self.tag_addresses[11] != 0)
                    @as(*TagEFI32SysTablePointer, @ptrFromInt(self.tag_addresses[11])) else null,
            TagEFI64SysTablePointer => return
                if (self.tag_addresses[12] != 0)
                    @as(*TagEFI64SysTablePointer, @ptrFromInt(self.tag_addresses[12])) else null,
            TagSMBIOSTables => return
                if (self.tag_addresses[13] != 0)
                    @as(*TagSMBIOSTables, @ptrFromInt(self.tag_addresses[13])) else null,
            TagACPIOldRSDP => return
                if (self.tag_addresses[14] != 0)
                    @as(*TagACPIOldRSDP, @ptrFromInt(self.tag_addresses[14])) else null,
            TagACPINewRSDP => return
                if (self.tag_addresses[15] != 0)
                    @as(*TagACPINewRSDP, @ptrFromInt(self.tag_addresses[15])) else null,
            TagNetInfo => return
                if (self.tag_addresses[16] != 0)
                    @as(*TagNetInfo, @ptrFromInt(self.tag_addresses[16])) else null,
            TagEFIMemMap => return
                if (self.tag_addresses[17] != 0)
                    @as(*TagEFIMemMap, @ptrFromInt(self.tag_addresses[17])) else null,
            TagEFIBootNotTerm => return
                if (self.tag_addresses[18] != 0)
                    @as(*TagEFIBootNotTerm, @ptrFromInt(self.tag_addresses[18])) else null,
            TagEFI32HandlePtr => return
                if (self.tag_addresses[19] != 0)
                    @as(*TagEFI32HandlePtr, @ptrFromInt(self.tag_addresses[19])) else null,
            TagEFI64HandlePtr => return
                if (self.tag_addresses[20] != 0)
                    @as(*TagEFI64HandlePtr, @ptrFromInt(self.tag_addresses[20])) else null,
            TagImageLoadBasePhysAddr => return
                if (self.tag_addresses[21] != 0)
                    @as(*TagImageLoadBasePhysAddr, @ptrFromInt(self.tag_addresses[21])) else null,
            else => return null
        }
        return null;

    }
};
