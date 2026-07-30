pub const IA32_APIC_BASE: u32 = 0x1B;

const krn = @import("kernel");
const arch = @import("../main.zig");
const std = @import("std");
const acpi = @import("../system/acpi.zig");

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

pub const MADTTYP_PROC_LAPIC: u8          = 0;
pub const MADTTYP_IOAPIC: u8              = 1;
pub const MADTTYP_IOAPIC_ISR: u8          = 2;
pub const MADTTYP_IOAPIC_NMI_SRC: u8      = 3;
pub const MADTTYP_LAPIC_NMI: u8           = 4;
pub const MADTTYP_LAPIC_ADDR_OVERRIDE: u8 = 5;
pub const MADTTYP_PROC_LX2APIC: u8        = 9;

pub const ProcessorLocalAPIC = packed struct {
    type:           u8, // 0
    length:         u8, // 8
    acpi_proc_id:   u8,
    apic_id:        u8,
    // flags lands at offset 4 with no padding (four u8s precede it).
    // bit 0 = enabled, bit 1 = online-capable.
    flags:          u32,
};

pub const IOAPIC = packed struct {
    type:           u8, // 1
    length:         u8, // 12
    io_apic_id:     u8,
    reserved:       u8,
    io_apic_addr:   u32,
    gsi_base:       u32,
};

pub const IOAPICInterruptSourceOverride = packed struct {
    type:           u8, // 2
    length:         u8, // 10
    bus_source:     u8,
    irq_source:     u8,
    gsi:            u32,
    flags:          u16,
};

pub const MADTEntry = extern struct {
    type:   u8,
    length: u8,
};

pub const MADT = extern struct {
    header: acpi.SDTHeader,
    local_address: u32,
    flags: u32,

    pub fn getNextEntry(self: *MADT, prev_entry: ?*MADTEntry) ?*MADTEntry {
        const table_end: usize = @intFromPtr(self) + self.header.Length;
        var next: usize = undefined;
        if (prev_entry) |prev| {
            if (prev.length == 0)
                return null;
            next = @intFromPtr(prev) + prev.length;
        } else {
            next = @intFromPtr(self) + @sizeOf(MADT);
        }
        // Need at least the 2-byte entry header, and the whole entry, in bounds.
        if (next + @sizeOf(MADTEntry) > table_end)
            return null;
        const ret: *MADTEntry = @ptrFromInt(next);
        if (ret.length == 0 or next + ret.length > table_end)
            return null;
        return ret;
    }
};
