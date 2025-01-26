const pmm = @import("./pmm.zig").PMM;
const vmm = @import("./vmm.zig").VMM;
const printf = @import("debug").printf;
const PAGE_SIZE = @import("./memory.zig").PAGE_SIZE;

pub const FreeListNode = packed struct {
    block_size: u32,
    next: ?* FreeListNode,
};

pub const AllocHeader = packed struct {
    block_size: u32,
    head: ?*FreeList,
};

pub const FreeList = packed struct {
    size: u32,
    used: u32,
    data: u32, // virtual address
    head: ?*FreeListNode,
    vmm:  *vmm,
    pmm:  *pmm,

    pub fn init(phys_mm: *pmm, virt_mm: *vmm) FreeList {
        const start_addr: u32 = virt_mm.find_free_addr(); 
        // start_addr can potentially be 0xFFFFFFFF which means
        // there is no virt address space left for kheap.
        // FIX it
        return FreeList{
            .size = 0,
            .used = 0,
            .data = start_addr,
            .head = null,
            .vmm = virt_mm,
            .pmm = phys_mm,
        };
    }

    // This is a mess, it needs to be refactored
    pub fn alloc(self: *FreeList, size: u32) u32 {
        var buffer: ?*FreeListNode = self.head; 
        var total_size = size + @sizeOf(AllocHeader);
        if (total_size % 4 != 0)
            total_size += 4 - total_size % 4;
        while (buffer != null) : (buffer = buffer.?.next) {
            if (buffer.?.next == null)
                break;
            // check if node with block_size is of total_size
            // remove from linked list
            // arrange free list nodes
            // place header
            // return address to beginning of data
        }
        var num_pages = total_size / PAGE_SIZE;
        if (total_size % PAGE_SIZE != 0)
            num_pages += 1;
        const pfn: u32 = self.pmm.alloc_pages(num_pages);
        var idx: u32 = 0;
        while (idx < num_pages) : (idx += 1) {
            const physical = pfn + idx * PAGE_SIZE;
            const virtual = self.data + (self.size + idx) * PAGE_SIZE;
            self.vmm.map_page(virtual, physical); 
        }
        const begin = self.data + self.size * PAGE_SIZE;
        self.size += num_pages;
        const chunk: *AllocHeader = @ptrFromInt(begin);
        chunk.block_size = total_size; // Subject to change
        chunk.head = self;
        const free_node : *FreeListNode = @ptrFromInt(begin + chunk.block_size);
        if (buffer != null) {
            buffer.?.next = free_node;
        } else {
            self.head = free_node;
        }
        return begin + @sizeOf(AllocHeader);
    }
};
