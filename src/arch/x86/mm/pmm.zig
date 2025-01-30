const printf = @import("debug").printf;

const std = @import("std");
const PAGE_SIZE = 4096;

const MAX_ORDER: usize = 10;
const MAX_ORDER_SIZE: u32 = 1 << 10;

const PagesChunk = struct {
    map: *u32,
    pfn: u32,
};

pub const PMM = struct {
    free_area: []u32,
    index: u32,
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
            pmm.free_area[pmm.index] = ph_addr;
            pmm.index += 1;
        }
        pmm.index -= 1;
        return pmm;
    }

    // Alloc num of contigueous physical pages
    pub fn alloc_pages(self: *PMM, num: u32) u32 {
        var cont_size: u32 = 0;
        var idx: u32 = 0;
        var curr_pos: u32 = self.index;
        var ret_addr: u32 = 0;

        while (curr_pos >= 0 and self.free_area[self.index] != 0) {
            cont_size = 0;
            idx = curr_pos;
            if (curr_pos < num)
                return ret_addr;
            while (idx >= 0 and self.free_area[idx] != 0 and cont_size < num) {
                cont_size += 1;
                if (idx == 0) {
                    if (cont_size == num) {
                        ret_addr = self.free_area[idx];
                        @memset(self.free_area[idx..curr_pos + 1], 0);
                        while(self.index > 0 and self.free_area[self.index] == 0) : (self.index -= 1) {}
                        return ret_addr;
                    }
                    break;
                }
                idx -= 1;
            }
            if (cont_size == num) {
                ret_addr = self.free_area[idx + 1];
                @memset(self.free_area[idx + 1..curr_pos + 1], 0);
                while(self.index > 0 and self.free_area[self.index] == 0) : (self.index -= 1) {}
                return ret_addr;
            }
            curr_pos = idx;
            while(curr_pos > 0 and self.free_area[curr_pos] == 0) : (curr_pos -= 1) {} 
        }
        return ret_addr;
    }

    /// Allocate a page.
    ///
    /// Returns:
    ///     physical address : u32
    pub fn alloc_page(self: *PMM) u32 {
        const pf_addr = self.free_area[self.index];
        self.free_area[self.index] = 0;
        while(self.index > 0 and self.free_area[self.index] == 0) : (self.index -= 1) {}
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
        self.free_area[index] = pfn;
        if (index > self.index)
            self.index =index;
    }
};
// TODO Map memory for the kernel to use in the PMM
