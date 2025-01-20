const multiboot_info = @import("../boot/multiboot.zig").multiboot_info;
const multiboot_memory_map = @import("../boot/multiboot.zig").multiboot_memory_map;
const assert = @import("std").debug.assert;
const std = @import("std");

pub const mm = struct {
    avail: u64,
    base: u32,
};

pub const PAGE_OFFSET: u32 = 0xC0000000;
pub const PAGE_SIZE: u32 = 4096;

extern var _kernel_end: u32;
extern var _kernel_start: u32;

pub fn virt_to_phys(comptime T: type, addr: *T) *T {
    return @ptrFromInt(@intFromPtr(addr) - PAGE_OFFSET);
}

pub fn phys_to_virt(comptime T: type, addr: *T) *T {
    return @ptrFromInt(@intFromPtr(addr) + PAGE_OFFSET);
}

const page = packed struct {
    order: u4,
    ref_count: usize,
    // PG_active
    // PG_arch_1
    // PG_checked	Only used by the Ext2 filesystem
    // PG_dirty
    // PG_error
    // PG_fs_1
    // PG_highmem
    // PG_launder
    // PG_locked
    // PG_lru
    // PG_referenced
    // PG_reserved
    // PG_slab
    // PG_skip
    // PG_unused	This bit is literally unused
    // PG_uptodate
    flags: usize,
    // virtual address only if ZONE_HIGHMEM is implemented

};

// pub const list_head = struct {
//     next: ?*list_head,
//     prev: ?*list_head,
// };

// // put page
// pub fn containerOf(
//     comptime ParentType: type,
//     comptime FieldName: []const u8,
//     field_ptr: *align(1) const anyopaque,
// ) *ParentType {
//     // TODO add comptime check and move to different
//     // Get the offset of the field within the parent struct
//     const field_offset = @offsetOf(ParentType, FieldName);
//     // Convert the field pointer to an address
//     const field_addr = @intFromPtr(field_ptr);
//     // Subtract the offset to get the parent struct address
//     const parent_addr = field_addr - field_offset;
//     // Convert back to a pointer of the parent type
//     return @ptrFromInt(parent_addr);
// }

// const temp = struct {
//     val: i32,
//     list: list_head,
// }

const pmm = struct {
    order: u8,

};

// pub var TOTAL_FRAMES: u32 = undefined;
pub var base: u32 = undefined;
pub var mem_size: u64 = 0;
const ten_order: u32 = 1 << 10;

// get the first availaanle address and put metadata there
pub fn mm_init(info: *multiboot_info) mm {
    var i: u32 = 0;

    // Find the biggest memory region in memory map provided by multiboot
    while (i < info.mmap_length) : (i += @sizeOf(multiboot_memory_map)) {
        const mmap: *multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        if (mmap.len[0] > 0 and mmap.type == 1 and mmap.len[0] > mem_size) {
            mem_size = mmap.len[0];
            base = mmap.addr[0];
        }
    }
    const kernel_end: u32 = @intFromPtr(&_kernel_start) + @intFromPtr(&_kernel_end) - 0xC0000000;
    if (base < kernel_end) {
        base = kernel_end;
        mem_size -= kernel_end - base;
    }
    if ((base % PAGE_SIZE) > 0) {
        mem_size = mem_size - (base & 0xfff);
        base = (base & 0xfffff000) + PAGE_SIZE;
    }
    const ptr : *u8 = @ptrFromInt(0x00c00000);
    ptr.* = 42;
    // At this point we have page aligned
    // memory base and size. We now need
    // initialize page metadata on this address
    // for our buddy allocator. 
    // At this point we need to make sure that the memory we are
    // accesing is mapped inside our virtual address space. !!!

    // while(block < block + ten_order * PAGE_SIZE) : (block += ten_order * PAGE_SIZE) {
    //     ptr.order = 10;
    //     ptr.flags = 0;
    //     ptr.ref_count = 0;
    // }
    return mm{ .avail = mem_size, .base = base };
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
