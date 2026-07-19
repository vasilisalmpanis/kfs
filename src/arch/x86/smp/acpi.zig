pub const IA32_APIC_BASE: u32 = 0x1B;
const krn = @import("kernel");
const arch =@import("../main.zig");
const std = @import("std");

// get APIC base address
// rdmsr 0x1B

pub const ApicBaseMsr = packed struct(u64) {
    reserved0: u8 = 0,       // bits 0-7
    is_bsp: bool = false,    // bit 8: bootstrap processor
    reserved1: u1 = 0,       // bit 9
    x2apic_enable: bool = false, // bit 10
    apic_global_enable: bool = false, // bit 11
    base_addr: u24 = 0,      // bits 12-35: physical base address (page-aligned, shifted right by 12)
    reserved2: u28 = 0,      // bits 36-63

    pub fn physAddr(self: ApicBaseMsr) u64 {
        return @as(u64, self.base_addr) << 12;
    }
};

pub const SDT_header = extern struct {
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
    header:     SDT_header,
    // entries:    [*]u32,
    //
    pub fn entries(self: *RSDT) []u32 {
        const self_addr: u32 = @intFromPtr(self);
        const RSDTentries: [*]u32 = @ptrFromInt(self_addr + @sizeOf(SDT_header));
        const num_entries: u32 = (self.header.Length - @sizeOf(SDT_header)) / @sizeOf(u32);
        return RSDTentries[0..num_entries];
    }
};

pub const RSDPDescriptor = extern struct {
    signature:      [8]u8,
    checksum:       u8,
    oem_id:         [6]u8,
    revision:       u8,
    rsdt_address:   u32,
};

pub fn rdmsr(register: u32) u64 {
    var eax: u32 = 0;
    var edx: u32 = 0;
    asm volatile(
        \\ rdmsr
        :   [eax] "={eax}" (eax),
            [edx] "={edx}" (edx),
        :   [register] "{ecx}" (register),
        :   .{ .memory = true }
    );
    return (@as(u64, edx) << 32) | @as(u64, eax);
}

const temp = extern struct {
    local_address: u32,
    flags: u32,
};

pub fn init() void {
    // const res = rdmsr(IA32_APIC_BASE);
    // const acpi_info = @as(ApicBaseMsr,@bitCast(res));
    // krn.logger.INFO("RDMSR result {any}\n", .{acpi_info});
    //
    // const acpi_page: u32 = krn.mm.virt_memory_manager.findFreeSpace(1, 0xC0000000, 0xFFFFF000, false);
    // if (acpi_page == 0xFFFFFFFF)
    //     return;
    // const virt = krn.mm.virt_memory_manager.mapPage(acpi_page, acpi_info.physAddr(), .{.present = true, .writable = true});
    //
    const acpi_tag: *arch.multiboot.TagACPIOldRSDP = krn.boot_info.getTag(arch.multiboot.TagACPIOldRSDP) orelse return;
    const rsdp: *RSDPDescriptor = @ptrFromInt(@intFromPtr(acpi_tag) + @sizeOf(arch.multiboot.TagACPIOldRSDP));
    krn.logger.INFO("RSPP Signature: {s}\n", .{rsdp.signature});
    krn.logger.INFO("RSPP OEM: {s}\n", .{rsdp.oem_id});
    krn.logger.INFO("RSPP add: {x}\n", .{rsdp.rsdt_address});
    krn.logger.INFO("RSPP {any}\n", .{rsdp.*});
    const rsdt_page: u32 = krn.mm.virt_memory_manager.findFreeSpace(1, 0xC0000000, 0xFFFFF000, false);
    if (rsdt_page == 0xFFFFFFFF)
        return;
    const phys_rsdt_address = arch.pageAlign(rsdp.rsdt_address, true);
    krn.mm.virt_memory_manager.mapPage(rsdt_page, phys_rsdt_address, .{.present = true, .writable = true});
    const rsdt_address: u32 = rsdt_page + rsdp.rsdt_address % krn.mm.PAGE_SIZE;
    const rsdt: *RSDT = @ptrFromInt(rsdt_address);
    krn.logger.INFO("RSDT address: {x}\n", .{@intFromPtr(rsdt)});
    krn.logger.INFO("RSDT signature: {s}\n", .{rsdt.header.Signature});
    krn.logger.INFO("RSDT OEMId: {s}\n", .{rsdt.header.OEMID});
    krn.logger.INFO("RSDT OEMTableId: {s}\n", .{rsdt.header.OEMTableID});

    for (rsdt.entries()) |entry| {
        const header: *SDT_header = @ptrFromInt(rsdt_page + entry % krn.mm.PAGE_SIZE);
        krn.logger.INFO("Entry signature: {s}\n", .{header.Signature});
        if (std.mem.eql(u8, header.Signature[0..4], "APIC")) {
            const local: *temp = @ptrFromInt(rsdt_page + @sizeOf(SDT_header) + entry % krn.mm.PAGE_SIZE);
            krn.logger.INFO("ACPI local address {x} flags {x}\n", .{local.local_address, local.flags});
        }
    }
}
