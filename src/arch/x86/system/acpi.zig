const krn = @import("kernel");
const arch =@import("../main.zig");
const std = @import("std");

pub const SDTHeader = extern struct {
    Signature:          [4]u8,
    Length:             u32,
    Revision:           u8,
    Checksum:           u8,
    OEMID:              [6]u8,
    OEMTableID:         [8]u8,
    OEMRevision:        u32,
    CreatorID:          u32,
    CreatorRevision:    u32,
};

pub const RSDT = extern struct {
    header:     SDTHeader,

    pub fn entries(self: *RSDT) []u32 {
        const self_addr: u32 = @intFromPtr(self);
        const RSDTentries: [*]u32 = @ptrFromInt(self_addr + @sizeOf(SDTHeader));
        const num_entries: u32 = (self.header.Length - @sizeOf(SDTHeader)) / @sizeOf(u32);
        return RSDTentries[0..num_entries];
    }

    pub fn getEntery(self: *RSDT, signamture: []const u8) ?*SDTHeader {
        for (self.entries()) |ent_addr| {
            const header: *SDTHeader = @ptrFromInt(rsdt_page + ent_addr % krn.mm.PAGE_SIZE);
            if (std.mem.eql(u8, header.Signature[0..4], signamture)) {
                return header;
            }
        }
        return null;
    }
};

pub const RSDPDescriptor = extern struct {
    signature:      [8]u8,
    checksum:       u8,
    oem_id:         [6]u8,
    revision:       u8,
    rsdt_address:   u32,
};

pub var rsdt: ?*RSDT = null;
var rsdt_page: u32 = 0;

pub fn init() void {
    const acpi_tag = krn.boot_info.getTag(arch.multiboot.TagACPIOldRSDP)
        orelse return;
    const rsdp: *RSDPDescriptor = @ptrFromInt(
        @intFromPtr(acpi_tag) + @sizeOf(arch.multiboot.TagACPIOldRSDP)
    );
    rsdt_page = krn.mm.virt_memory_manager.findFreeSpace(
        1,
        0xC0000000,
        0xFFFFF000,
        false
    );
    if (rsdt_page == 0xFFFFFFFF)
        return;
    const phys_rsdt_address = arch.pageAlign(rsdp.rsdt_address, true);
    krn.mm.virt_memory_manager.mapPage(
        rsdt_page,
        phys_rsdt_address,
        .{ .present = true, .writable = true }
    );
    const rsdt_address: u32 = rsdt_page + rsdp.rsdt_address % krn.mm.PAGE_SIZE;
    rsdt = @ptrFromInt(rsdt_address);
}
