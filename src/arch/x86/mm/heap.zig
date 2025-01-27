const pmm = @import("./pmm.zig").PMM;
const vmm = @import("./vmm.zig").VMM;
const printf = @import("debug").printf;
const dbg = @import("debug");
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

    fn _expand_free_area(self: *FreeList, size: u32) u32 {
        var num_pages = size / PAGE_SIZE;
        if (size % PAGE_SIZE != 0)
            num_pages += 1;
        var physical = self.pmm.alloc_pages(num_pages);
        var virtual = self.data + self.size * PAGE_SIZE;
        var idx: u32 = 0;
        while (idx < num_pages): (idx += 1) {
            self.vmm.map_page(virtual, physical);
            physical += PAGE_SIZE;
            virtual += PAGE_SIZE;
        }
        self.size += num_pages;
        return num_pages * PAGE_SIZE;
    }

    // This is a mess, it needs to be refactored
    pub fn alloc(self: *FreeList, size: u32) u32 {
        var total_size = size + @sizeOf(AllocHeader);
        if (total_size % 4 != 0)
            total_size += 4 - total_size % 4;
        var buffer: ?*FreeListNode = self.head;
        var prev = self.head;
        while (buffer != null) : (buffer = buffer.?.next) {
            if (buffer.?.block_size >= total_size) {
                const block_size = buffer.?.block_size;
                const next: ?*FreeListNode = buffer.?.next;
                const addr: u32 = @intFromPtr(buffer);
                var header: *AllocHeader = @ptrFromInt(addr);
                header.block_size = total_size;
                header.head = self;
                if (block_size > total_size + @sizeOf(FreeListNode)) {
                    var free_header: *FreeListNode = @ptrFromInt(addr + total_size);
                    free_header.block_size = block_size - total_size;
                    free_header.next = next;
                    if (@intFromPtr(prev) == @intFromPtr(buffer)) {
                        self.head = free_header;
                    } else {
                        prev.?.next = free_header;
                    }
                } else {
                    prev.?.next = buffer.?.next;
                }
                return addr;
            }
            if (buffer.?.next == null)
                break;
            prev = buffer;
        }
        const begin = self.data + self.size * PAGE_SIZE;
        const free_size = self._expand_free_area(total_size);
        const chunk: *AllocHeader = @ptrFromInt(begin);
        chunk.block_size = total_size; // Subject to change
        chunk.head = self;
        if (free_size > chunk.block_size + @sizeOf(FreeListNode)) {
            const free_node : *FreeListNode = @ptrFromInt(begin + chunk.block_size);
            free_node.block_size = free_size - chunk.block_size;
            free_node.next = null;
            if (buffer != null) {
                buffer.?.next = free_node;
            } else {
                self.head = free_node;
            }
        }
        return begin + @sizeOf(AllocHeader);
    }
};
