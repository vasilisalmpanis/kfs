const printf = @import("drivers").printf;

const std = @import("std");
const PAGE_SIZE = @import("memory.zig").PAGE_SIZE;

const MAX_ORDER: usize = 10;
const MAX_ORDER_SIZE: u32 = 1 << 10;

const PagesChunk = struct {
    map: *u32,
    pfn: u32,
};

pub const PMM = struct {
    free_area: []u32,
    index: i32,
    size: u64, // might be incorrect after occupying for system.
    begin: u32,
    end: u32,

    pub fn init(begin: u32, size: u64) PMM {
        const pageCount: usize = @intCast(size / PAGE_SIZE);
        var pmm = PMM{
            .free_area = @as([*]u32, @ptrFromInt(begin + 0xC0000000))[0..pageCount],
            .begin = begin,
            .size = size,
            .index = 0,
            .end = 0,
        };
        const memory_end = begin + size;
        var ph_addr = ((begin + pageCount * @sizeOf(usize)) & 0xfffff000) + PAGE_SIZE;
        pmm.begin = ph_addr;
        pmm.end = @intCast((memory_end & 0xfffff000) - PAGE_SIZE);
        while (ph_addr < pmm.end) : (ph_addr += PAGE_SIZE) {
            pmm.free_area[@intCast(pmm.index)] = ph_addr;
            pmm.index += 1;
        }
        pmm.index -= 1;
        return pmm;
    }


    /// Allocate a page.
    ///
    /// Returns:
    ///     physical address : u32
    pub fn alloc_page(self: *PMM) u32 {
        var pf_addr : u32 = 0;
        if (self.index == -1)
            return 0;
        while(self.free_area[@intCast(self.index)] == 0) : (self.index -= 1) {}
        if (self.index == -1)
            return 0;
        pf_addr = self.free_area[@intCast(self.index)];
        self.free_area[@intCast(self.index)] = 0;
        self.index -= 1;
        return pf_addr;
    }
    /// Free a page.
    /// Put a page back on the stack using
    /// the physical address as a index. Keeps
    /// the addresses in sorted order.
    /// Returns:
    ///     void
    pub fn free_page(self: *PMM, pfn: u32) void {
        if (pfn % PAGE_SIZE > 0)
            return ;
        if (pfn < self.begin or pfn >= self.end)
            return ;
        // At this point address should be page aligned
        // and inside our managed physical memory space.

        // We use the PFN - BEGIN of managed memory
        // to retrieve an index inside the free_area
        // array and mark the physical address as free.
        const index: u32 = (pfn - self.begin) / PAGE_SIZE;
        self.free_area[@intCast(index)] = pfn;
        self.index = @intCast(index);
    }
};
// TODO Map memory for the kernel to use in the PMM
