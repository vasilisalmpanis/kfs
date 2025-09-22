const multiboot = @import("arch").multiboot;
const std = @import("std");
const arch = @import("arch");
const krn = @import("../main.zig");

const pmm = @import("arch").pmm;
const vmm = @import("arch").vmm;
const heap = @import("./heap.zig");
const printf = @import("debug").printf;
const dbg = @import("debug");

pub const proc_mm = @import("./proc_mm.zig");
pub const MM = @import("./proc_mm.zig").MM;
pub const MAP = @import("./proc_mm.zig").MAP;
pub const VMA = @import("./proc_mm.zig").VMA;
pub const PROT_READ = @import("./proc_mm.zig").PROT_READ;
pub const PROT_WRITE = @import("./proc_mm.zig").PROT_WRITE;
pub const PROT_RW: u32 = PROT_READ | PROT_WRITE;
pub const VASpair = vmm.VASpair;
pub const MAP_TYPE = @import("./proc_mm.zig").MAP_TYPE;

pub const kmalloc = @import("./kmalloc.zig").kmalloc;
pub const kmallocArray = @import("./kmalloc.zig").kmallocArray;
pub const kmallocSlice = @import("./kmalloc.zig").kmallocSlice;
pub const dupSlice = @import("./kmalloc.zig").dupSlice;
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

var fba: std.heap.FixedBufferAllocator = undefined;
pub var kernel_allocator: KernelAllocator = undefined;

const Allocator = @import("std").mem.Allocator;
const Alignment = @import("std").mem.Alignment;

pub const KernelAllocator = struct {
    pub fn allocator(self: *KernelAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(_: *anyopaque, n: usize, _: Alignment, _: usize) ?[*]u8 {
        return kmallocArray(u8, n);
    }
    fn free(_: *anyopaque, buf: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        kfree(buf.ptr);
    }

    fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn remap(
        context: *anyopaque,
        memory: []u8,
        alignment: Alignment,
        new_len: usize,
        return_address: usize,
    ) ?[*]u8 {
        return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
    }
};

// get the first availaanle address and put metadata there
pub fn mmInit(info: *multiboot.Multiboot) void {
    // var i: u32 = 0;
    if (info.getTag(multiboot.TagMemoryMap)) |tag| {
        const num_entries: u32 = (tag.size - @sizeOf(multiboot.TagMemoryMap)) / tag.entry_size;
        const entries = tag.getMemMapEntries();
        // Find the biggest memory region in memory map provided by multiboot
        for (0..num_entries) |idx| {
            const len: u32 = @truncate(entries[idx].length);
            if (len > 0 and entries[idx].type == 1 and len > mem_size) {
                mem_size = len;
                base = @truncate(entries[idx].base_addr);
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
    }

    kernel_allocator = KernelAllocator{};
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
