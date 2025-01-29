const pmm = @import("./pmm.zig").PMM;
const vmm = @import("./vmm.zig").VMM;
const printf = @import("debug").printf;
const dbg = @import("debug");
const PAGE_SIZE = @import("./memory.zig").PAGE_SIZE;

pub const FreeListNode = packed struct {
    block_size: u32,
    next: ?*FreeListNode,
};

pub const AllocHeader = packed struct {
    block_size: u32,
    head: ?*FreeList,
};

pub const FreeList = packed struct {
    size: u32,
    // WARNING: we need to be careful with size since
    // we use it to calculate begin of virt addr
    // to map. if we have 3 pages allocated and
    // the first one is free we would need to
    // adjust size and data.
    used: u32,
    data: u32, // virtual address
    head: ?*FreeListNode,
    vmm: *vmm,
    pmm: *pmm,

    pub fn init(phys_mm: *pmm, virt_mm: *vmm) FreeList {
        const start_addr: u32 = virt_mm.find_free_addr();
        // TODO: Handle case where start_addr is 0xFFFFFFFF (no virt address space left)
        // NOTE: start using invalid pointers like 0xDEADBEEF 0xCAFEBABE etc
        return FreeList{
            .size = 0,
            .used = 0,
            .data = start_addr,
            .head = null,
            .vmm = virt_mm,
            .pmm = phys_mm,
        };
    }

    fn insertNewFreeNode(self: *FreeList, new: *FreeListNode, old: *FreeListNode) void {
        const end_addr: u32 = @intFromPtr(new) + new.block_size;
        // New node is before head of free nodes
        if (@intFromPtr(new) < @intFromPtr(old)) {
            if (end_addr != @intFromPtr(old)) {
                new.next = self.head;
                self.head = new;
                return ;
            }
            // Merge
            new.block_size += self.head.?.block_size;
            new.next = old.next;
            self.head = new;
            return ;
        }
        var curr: *FreeListNode = new;
        // Handle node to the left of new node
        if (@intFromPtr(old) + old.block_size < @intFromPtr(new)) {
            new.next = old.next;
            old.next = new;
        } else {
            // Merge
            old.block_size += new.block_size;
            curr = old;
        }
        // Handle node to the right of new node
        if (old.next == null)
            return ;
        // Merge
        if (@intFromPtr(curr) + curr.block_size == @intFromPtr(old.next)) {
            curr.block_size += old.next.?.block_size;
            curr.next = old.next.?.next;
        }
    }

    pub fn free(self: *FreeList, addr: u32) void {
        var header: ?*AllocHeader = undefined;
        if (addr - @sizeOf(AllocHeader) < 0)
            return;
        const mem_max = self.data + self.size * PAGE_SIZE;
        if (addr < self.data or addr >= mem_max)
            return;
        header = @ptrFromInt(addr - @sizeOf(AllocHeader));
        if (header.?.head != self)
            return;

        // checks are OK we can iterate through list
        const block_size = header.?.block_size;
        // Do not use header variable after this line
        const new_node: *FreeListNode = @ptrFromInt(addr - @sizeOf(FreeListNode));
        new_node.block_size = block_size;
        new_node.next = null;
        if (self.head == null) {
            self.head = new_node;
            return ;
        }
        var current: ?*FreeListNode = self.head;
        if (@intFromPtr(current) > @intFromPtr(new_node))
            return self.insertNewFreeNode(new_node, current.?);
        while (@intFromPtr(current) < @intFromPtr(new_node)) : (current = current.?.next) {
            if (@intFromPtr(new_node) < @intFromPtr(current.?.next))
                return self.insertNewFreeNode(new_node, current.?);
            if (current.?.next == null)
                return self.insertNewFreeNode(new_node, current.?);
        }
    }

    pub fn alloc(self: *FreeList, size: u32) u32 {
        // Total size of the block to allocate (including header)
        const total_size = alignToPtr(size + @sizeOf(AllocHeader));
        
        // Try to find existing block (first fit)
        var buffer = self.head;
        var prev = self.head;
        while (buffer) |b| : (buffer = buffer.?.next) {
            if (b.block_size >= total_size) {
                return self.allocateFromBlock(
                    prev.?,
                    b,
                    total_size
                );
            }
            if (b.next == null) break;
            prev = buffer;
        }

        // Allocate new block if no existing block found
        return self.allocateNewBlock(total_size, buffer);
    }

    fn alignToPtr(value: u32) u32 {
        return if (value % 4 != 0) value + (4 - value % 4) else value;
    }

    fn allocateFromBlock(
        self: *FreeList, 
        prev: *FreeListNode,
        curr: *FreeListNode,
        total_size: u32
    ) u32 {
        const is_head: bool = (@intFromPtr(prev) == @intFromPtr(curr));
        const addr = @intFromPtr(curr);
        const free_block_size = curr.block_size;
        const next_free = curr.next;
        self.initAllocHeader(addr, total_size);

        if (free_block_size > total_size + @sizeOf(FreeListNode)) {
            self.addFreeNode(
                addr + total_size,
                free_block_size - total_size,
                if (is_head) null else prev,
                next_free
            );
        } else {
            if (is_head) {
                self.head = next_free;
            } else {
                prev.next = next_free;
            }
        }
        return addr + @sizeOf(AllocHeader);
    }

    fn initAllocHeader(self: *FreeList, addr: u32, size: u32) void {
        var header: *AllocHeader = @ptrFromInt(addr);
        header.block_size = size;
        header.head = self;
    }

    fn allocateNewBlock(
        self: *FreeList, 
        total_size: u32,
        last_block: ?*FreeListNode
    ) u32 {
        const begin = self.data + self.size * PAGE_SIZE;
        const free_size = self.expandMemory(total_size);
        self.initAllocHeader(begin, total_size);

        // If there is a space left for header plus something else add new free node
        if (free_size > total_size + @sizeOf(FreeListNode)) {
            self.addFreeNode(
                begin + total_size, 
                free_size - total_size,
                last_block,
                null
            );
        }
        return begin + @sizeOf(AllocHeader);
    }

    fn expandMemory(self: *FreeList, size: u32) u32 {
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

    fn addFreeNode(
        self: *FreeList,
        addr: u32, size: u32,
        prev: ?*FreeListNode,
        next: ?*FreeListNode
    ) void {
        const new_node: *FreeListNode = @ptrFromInt(addr);
        new_node.block_size = size;
        new_node.next = next;
        if (prev == null) {
            self.head = new_node;
        } else {
            prev.?.next = new_node;
        }
    }
};
