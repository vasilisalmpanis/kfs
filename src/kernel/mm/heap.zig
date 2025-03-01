const pmm = @import("arch").pmm.PMM;
const vmm = @import("arch").vmm.VMM;
const printf = @import("debug").printf;
const dbg = @import("debug");
const PAGE_SIZE = @import("./init.zig").PAGE_SIZE;

const AllocationError = error{
    OutOfMemory,
};

pub const FreeListNode = packed struct {
    block_size: u32,
    next: ?*FreeListNode,
    unused_1: u32 = 0,
    unused_2: u32 = 0,
};

pub const AllocHeader = packed struct {
    block_size: u32,
    head: ?*FreeList,
    unused_1: u32 = 0,
    unused_2: u32 = 0,
};

pub const FreeList = packed struct {
    start_addr: u32,
    end_addr: u32,
    head: ?*FreeListNode,
    vmm: *vmm,
    pmm: *pmm,
    alignement: u8 = 16,

    pub fn init(
        phys_mm: *pmm,
        virt_mm: *vmm,
        start_addr: u32,
        end_addr: u32,
        alignement: u8,
    ) FreeList {
        return FreeList{
            .start_addr = start_addr,
            .end_addr = end_addr,
            .head = null,
            .vmm = virt_mm,
            .pmm = phys_mm,
            .alignement = alignement,
        };
    }

    fn insertNewFreeNode(
        self: *FreeList,
        new: *FreeListNode,
        old: *FreeListNode,
        prev: ?*FreeListNode
    ) void {
        const end_addr: u32 = @intFromPtr(new) + new.block_size;
        var real_prev: ?*FreeListNode = prev;
        // New node is before head of free nodes
        if (@intFromPtr(new) < @intFromPtr(old)) {
            if (end_addr != @intFromPtr(old)) {
                new.next = self.head;
                self.head = new;
                self.return_free_pages(new, real_prev);
                return;
            }
            // Merge
            new.block_size += self.head.?.block_size;
            new.next = old.next;
            self.head = new;
            self.return_free_pages(new, real_prev);
            return;
        }
        var curr: *FreeListNode = new;
        // Handle node to the left of new node
        if (@intFromPtr(old) + old.block_size < @intFromPtr(new)) {
            new.next = old.next;
            old.next = new;
            real_prev = old;
        } else {
            // Merge
            old.block_size += new.block_size;
            curr = old;
        }
        // Handle node to the right of new node
        if (old.next == null) {
            self.return_free_pages(curr, real_prev);
            return;
        }
        // Merge
        if (@intFromPtr(curr) + curr.block_size == @intFromPtr(curr.next)) {
            curr.block_size += curr.next.?.block_size;
            curr.next = curr.next.?.next;
        }
        self.return_free_pages(curr, real_prev);
    }

    fn return_free_pages(
        self: *FreeList,
        node: ?*FreeListNode,
        prev: ?*FreeListNode
    ) void {
        const block_start: u32 = @intFromPtr(node);
        const node_after: ?*FreeListNode = node.?.next;
        const block_end: u32 = @intFromPtr(node) + node.?.block_size;
        var free_pages: u32 = 0;
        var page_start: u32 = 0;
        var remainder: u32 = 0;
        var node_before: ?*FreeListNode = undefined;
        var new_node: ?*FreeListNode = undefined;
        var returned: bool = false;

        if (node.?.block_size >= PAGE_SIZE) {
            if (block_start & 0xFFF != 0) {
                // not page aligned
                node_before = node;
                page_start = (@intFromPtr(node) & 0xFFFFF000) + PAGE_SIZE;
                if (page_start - block_start < @sizeOf(FreeListNode)) {
                    page_start += PAGE_SIZE;
                    if (page_start > block_start + node.?.block_size)
                        return;
                }
            } else {
                // page aligned
                node_before = prev;
                page_start = @intFromPtr(node);
            }
            remainder = block_start + node.?.block_size - page_start;
            if (remainder >= PAGE_SIZE) {
                free_pages = remainder / PAGE_SIZE;
                if (remainder % PAGE_SIZE < @sizeOf(FreeListNode)
                    and remainder % PAGE_SIZE > 0)
                    free_pages -= 1;
                for (0..free_pages) |page| {
                    self.vmm.unmap_page(page_start + page * PAGE_SIZE);
                    returned = true;
                }
                if (page_start > block_start and returned) {
                    node.?.block_size = page_start - block_start;
                }
                if (remainder % PAGE_SIZE == 0) {
                    if (node_before == null) {
                        self.head = node_after;
                    } else {
                        node_before.?.next = node_after;
                    }
                } else {
                    new_node = @ptrFromInt(page_start + free_pages * PAGE_SIZE);
                    new_node.?.next = node_after;
                    new_node.?.block_size = block_end - @intFromPtr(new_node);
                    if (node_before != null) {
                        node_before.?.next = new_node;
                    } else {
                        self.head = new_node;
                    }
                }
            }
        }
    }

    fn getAllocHeader(self: *FreeList, addr: u32) ?*AllocHeader {
        var header: ?*AllocHeader = undefined;
        if (addr - @sizeOf(AllocHeader) < 0)
            return null;
        if (addr < self.start_addr or addr >= self.end_addr)
            return null;
        header = @ptrFromInt(addr - @sizeOf(AllocHeader));
        if (header.?.head != self)
            return null;
        return header;
    }

    pub fn free(self: *FreeList, addr: u32) void {
        var prev: ?*FreeListNode = undefined;
        const header: ?*AllocHeader = self.getAllocHeader(addr);
        if (header == null)
            return;
        // checks are OK we can iterate through list
        const block_size = header.?.block_size;
        // Do not use header variable after this line
        const new_node: *FreeListNode = @ptrFromInt(addr - @sizeOf(FreeListNode));
        new_node.block_size = block_size;
        new_node.next = null;
        if (self.head == null) {
            self.head = new_node;
            self.return_free_pages(new_node, null);
            return;
        }
        var current: ?*FreeListNode = self.head;
        prev = null;
        if (@intFromPtr(current) > @intFromPtr(new_node))
            return self.insertNewFreeNode(new_node, current.?, prev);
        while (
            @intFromPtr(current) < @intFromPtr(new_node)
        ) : (current = current.?.next) {
            if (@intFromPtr(new_node) < @intFromPtr(current.?.next))
                return self.insertNewFreeNode(new_node, current.?, prev);
            if (current.?.next == null)
                return self.insertNewFreeNode(new_node, current.?, prev);
            prev = current;
        }
    }

    pub fn alloc(
        self: *FreeList,
        size: u32,
        contig: bool,
        user: bool
    ) !u32 {
        // Total size of the block to allocate (including header)
        const total_size = self.alignToPtr(size + @sizeOf(AllocHeader));

        // Try to find existing block (first fit)
        var buffer = self.head;
        var prev = self.head;
        while (buffer) |b| : (buffer = buffer.?.next) {
            if (b.block_size >= total_size) {
                return self.allocateFromBlock(prev.?, b, total_size);
            }
            if (b.next == null) break;
            prev = buffer;
        }

        // Allocate new block if no existing block found
        return try self.allocateNewBlock(
            total_size,
            buffer,
            contig,
            user
        );
    }

    fn alignToPtr(self: *FreeList, value: u32) u32 {
        return
            if (value % self.alignement != 0)
                value + (self.alignement - value % self.alignement)
            else
                value;
    }

    fn allocateFromBlock(
        self: *FreeList,
        prev: *FreeListNode,
        curr: *FreeListNode,
        total_size: u32
    ) u32 {
        const is_head: bool = (@intFromPtr(self.head.?) == @intFromPtr(curr));
        const addr = @intFromPtr(curr);
        const free_block_size = curr.block_size;
        const next_free = curr.next;
        var block_size = total_size;
        if (free_block_size - total_size <= self.alignement) {
            block_size += free_block_size - total_size;
        }
        self.initAllocHeader(addr, block_size);

        if (free_block_size > block_size + @sizeOf(FreeListNode)) {
            self.addFreeNode(
                addr + block_size,
                free_block_size - block_size,
                if (is_head) null else prev, next_free
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
        last_block: ?*FreeListNode,
        contig: bool,
        user: bool
    ) !u32 {
        var num_pages = total_size / PAGE_SIZE;
        var block_size = total_size;
        if (total_size % PAGE_SIZE != 0)
            num_pages += 1;
        const begin = self.vmm.find_free_space(
            num_pages,
            self.start_addr,
            self.end_addr,
            user
        );
        if (begin == 0xFFFFFFFF)
            return AllocationError.OutOfMemory;
        const free_size = try if (contig)
            self.expandMemoryContig(num_pages, begin, user)
        else
            self.expandMemory(num_pages, begin, user);
        if (free_size - total_size <= self.alignement)
            block_size += free_size - total_size;
        self.initAllocHeader(begin, block_size);

        // If there is a space left for header plus something else add new free node
        if (free_size > block_size + @sizeOf(FreeListNode)) {
            self.addFreeNode(
                begin + block_size,
                free_size - block_size,
                last_block,
                null
            );
        }
        return begin + @sizeOf(AllocHeader);
    }

    fn expandMemoryContig(self: *FreeList, num_pages: u32, virtual: u32, user: bool) !u32 {
        var physical = self.pmm.alloc_pages(num_pages);
        if (physical == 0) {
            return AllocationError.OutOfMemory;
        }
        var idx: u32 = 0;
        var virt_addr = virtual;
        while (idx < num_pages) : (idx += 1) {
            self.vmm.map_page(virt_addr, physical, user);
            physical += PAGE_SIZE;
            virt_addr += PAGE_SIZE;
        }
        return num_pages * PAGE_SIZE;
    }

    fn expandMemory(self: *FreeList, num_pages: u32, virtual: u32, user: bool) !u32 {
        var idx: u32 = 0;
        var virt_addr = virtual;
        while (idx < num_pages) : (idx += 1) {
            const physical = self.pmm.alloc_page();
            if (physical == 0) {
                // Unmap all the previous mapped pages
                while (idx > 0) : (idx -= 1) {
                    virt_addr -= PAGE_SIZE;
                    self.vmm.unmap_page(virt_addr);
                }
                return AllocationError.OutOfMemory;
            }
            self.vmm.map_page(virt_addr, physical, user);
            virt_addr += PAGE_SIZE;
        }
        return num_pages * PAGE_SIZE;
    }

    fn addFreeNode(
        self: *FreeList,
        addr: u32,
        size: u32,
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

    pub fn get_size(self: *FreeList, addr: u32) u32 {
        const header: ?*AllocHeader = self.getAllocHeader(addr);
        if (header == null)
            return 0;
        return header.?.block_size - @sizeOf(AllocHeader);
    }
};
