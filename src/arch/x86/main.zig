pub const io = @import("io.zig");
pub const system = @import("system/system.zig");
pub const gdt = @import("gdt.zig");
pub const multiboot = @import("boot/multiboot.zig");
pub const vmm = @import("mm/vmm.zig");
pub const pmm = @import("mm/pmm.zig");
pub const idt = @import("idt.zig");
pub const regs = @import("system/cpu.zig").registers_t;

pub const PAGE_SIZE = @import("mm/pmm.zig").PAGE_SIZE;
