const multiboot_info = @import("arch").multiboot.MultibootInfo;
const multiboot_memory_map = @import("arch").multiboot.MultibootMemoryMap;
const std = @import("std");
const arch = @import("arch");

const pmm = @import("arch").pmm;
const vmm = @import("arch").vmm;
const heap = @import("./heap.zig");
const printf = @import("debug").printf;
const dbg = @import("debug");

pub const proc_mm = @import("./proc_mm.zig");
pub const MM = @import("./proc_mm.zig").MM;

pub const kmalloc = @import("./kmalloc.zig").kmalloc;
pub const kmalloc = @import("./kmalloc.zig").kmalloc;
pub const kmallocArray = @import("./kmalloc.zig").kmallocArray;
pub const kfree = @import("./kmalloc.zig").kfree;
pub const kfree = @import("./kmalloc.zig").kfree;
pub const ksize = @import("./kmalloc.zig").ksize;
pub const vmalloc = @import("./vmalloc.zig").vmalloc;
pub const vfree = @import("./vmalloc.zig").vfree;
pub const vsize = @import("./vmalloc.zig").vsize;

pub const PAGE_OFFSET: u32 = 0xC0000000;
pub const PAGE_SIZE: u32 = arch.PAGE_SIZE;

extern const _kernel_end: u32;
extern const _kernel_start: u32;

pub fn virtToPhys(comptime T: type, addr: *T) *T {
    return @ptrFromInt(@intFromPtr(addr) - PAGE_OFFSET);
}

pub fn physToVirt(comptime T: type, addr: *T) *T {
    return @ptrFromInt(@intFromPtr(addr) + PAGE_OFFSET);
}

pub var base: u32 = undefined;
pub var mem_size: u64 = 0;

var phys_memory_manager: pmm.PMM = undefined;
pub var virt_memory_manager: vmm.VMM = undefined;
pub var kheap: heap.FreeList = undefined;
pub var vheap: heap.FreeList = undefined;
pub var uheap: heap.FreeList = undefined;

// get the first availaanle address and put metadata there
pub fn mmInit(info: *multiboot_info) void {
    var i: u32 = 0;

    // Find the biggest memory region in memory map provided by multiboot
    while (i < info.mmap_length) : (i += @sizeOf(multiboot_memory_map)) {
        const mmap: *multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        if (mmap.len[0] > 0 and mmap.type == 1 and mmap.len[0] > mem_size) {
            mem_size = mmap.len[0];
            base = mmap.addr[0];
        }
    }
    const kernel_end: u32 = @intFromPtr(&_kernel_end) - 0xC0000000;
    if (base < kernel_end) {
        mem_size -= kernel_end - base;
        base = kernel_end;
    }
    if ((base % PAGE_SIZE) > 0) {
        mem_size = mem_size - (base & 0xfff);
        base = (base & 0xfffff000) + PAGE_SIZE;
    }
    // At this point we have page aligned
    // memory base and size.
    // At this point we need to make sure that the memory we are
    // accesing is mapped inside our virtual address space. !!!
    phys_memory_manager = pmm.PMM.init(base, mem_size);
    virt_memory_manager = vmm.VMM.init(&phys_memory_manager);
    kheap = heap.FreeList.init(
        &phys_memory_manager,
        &virt_memory_manager,
        PAGE_OFFSET,
        0xFFFFF000,
        16
    );
    vheap = heap.FreeList.init(
        &phys_memory_manager,
        &virt_memory_manager,
        PAGE_OFFSET,
        0xFFFFF000,
        16
    );
    uheap = heap.FreeList.init(
        &phys_memory_manager,
        &virt_memory_manager,
        PAGE_SIZE,
        PAGE_OFFSET,
        16
    );
}

// create page

// FREE AREA ARRAY
// 0
// 1
// 2
// 3
// 4
// 5
// 6
// 7
// 8 (ORDER - 2) Linked list of Free blocks of order 9
// 9 (ORDER - 1) Linked list of Free blocks of order 10

// get page

// INFO about PMM
// 1. Set aside a region of memory for each block allocated
