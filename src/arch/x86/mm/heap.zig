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

    fn expand_free_area(self: *FreeList, size: u32) u32 {
        const num_pages = calculateRequiredPages(size);
        const physical = self.pmm.alloc_pages(num_pages);
        const virtual = self.data + self.size * PAGE_SIZE;

        mapPages(self, virtual, physical, num_pages);
        self.size += num_pages;

        return num_pages * PAGE_SIZE;
    }

    fn calculateRequiredPages(size: u32) u32 {
        var pages = size / PAGE_SIZE;
        if (size % PAGE_SIZE != 0) {
            pages += 1;
        }
        return pages;
    }

    fn mapPages(self: *FreeList, virtual: u32, physical: u32, num_pages: u32) void {
        var idx: u32 = 0;
        var curr_virtual = virtual;
        var curr_physical = physical;

        while (idx < num_pages) : (idx += 1) {
            self.vmm.map_page(curr_virtual, curr_physical);
            curr_physical += PAGE_SIZE;
            curr_virtual += PAGE_SIZE;
        }
    }

    fn init_block(self: *FreeList, total_size: u32, buffer: ?*FreeListNode) u32 {
        const begin = self.data + self.size * PAGE_SIZE;
        const free_size = self.expand_free_area(total_size);

        const chunk = initializeChunk(begin, total_size, self);

        if (canCreateFreeNode(free_size, chunk.block_size)) {
            const free_node = createFreeNode(begin, chunk.block_size, free_size);
            linkFreeNode(self, buffer, free_node);
        }

        return begin;
    }

    fn initializeChunk(addr: u32, size: u32, head: *FreeList) *AllocHeader {
        const chunk: *AllocHeader = @ptrFromInt(addr);
        chunk.block_size = size;
        chunk.head = head;
        return chunk;
    }

    fn canCreateFreeNode(free_size: u32, block_size: u32) bool {
        return free_size > block_size + @sizeOf(FreeListNode);
    }

    fn createFreeNode(begin: u32, block_size: u32, free_size: u32) *FreeListNode {
        const free_node: *FreeListNode = @ptrFromInt(begin + block_size);
        free_node.block_size = free_size - block_size;
        free_node.next = null;
        return free_node;
    }

    fn linkFreeNode(self: *FreeList, buffer: ?*FreeListNode, free_node: *FreeListNode) void {
        if (buffer != null) {
            buffer.?.next = free_node;
        } else {
            self.head = free_node;
        }
    }

    fn align_size(size: u32) u32 {
        if (size % 4 != 0) {
            return size + (4 - size % 4);
        }
        return size;
    }

    pub fn alloc(self: *FreeList, size: u32) u32 {
        const total_size = align_size(size) + @sizeOf(AllocHeader);

        if (findSuitableBlock(self, total_size)) |result|
            return result;

        return self.init_block(total_size, self.head) + @sizeOf(AllocHeader);
    }

    fn findSuitableBlock(self: *FreeList, total_size: u32) ?u32 {
        var buffer: ?*FreeListNode = self.head;
        var prev = self.head;

        while (buffer != null) : (buffer = buffer.?.next) {
            if (buffer.?.block_size >= total_size) {
                return handleFoundBlock(self, buffer.?, prev, total_size);
            }

            if (buffer.?.next == null) break;
            prev = buffer;
        }

        return null;
    }

    fn handleFoundBlock(self: *FreeList, buffer: *FreeListNode, prev: ?*FreeListNode, total_size: u32) u32 {
        const block_size = buffer.block_size;
        const next = buffer.next;
        const addr: u32 = @intFromPtr(buffer);

        if (block_size > total_size + @sizeOf(FreeListNode)) {
            handleBlockSplit(self, addr, total_size, block_size, next, prev, buffer);
        } else {
            updateFreeList(self, prev, buffer);
        }

        return addr;
    }

    fn initializeHeader(addr: u32, size: u32, head: *FreeList) *AllocHeader {
        var header: *AllocHeader = @ptrFromInt(addr);
        header.block_size = size;
        header.head = head;
        return header;
    }

    fn handleBlockSplit(
        self: *FreeList,
        addr: u32,
        total_size: u32,
        block_size: u32,
        next: ?*FreeListNode,
        prev: ?*FreeListNode,
        buffer: *FreeListNode,
    ) void {
        const free_header = createSplitFreeNode(addr, total_size, block_size, next);

        if (@intFromPtr(prev) == @intFromPtr(buffer)) {
            self.head = free_header;
        } else {
            prev.?.next = free_header;
        }
    }

    fn createSplitFreeNode(
        addr: u32,
        total_size: u32,
        block_size: u32,
        next: ?*FreeListNode,
    ) *FreeListNode {
        var free_header: *FreeListNode = @ptrFromInt(addr + total_size);
        free_header.block_size = block_size - total_size;
        free_header.next = next;
        return free_header;
    }

    fn updateFreeList(self: *FreeList, prev: ?*FreeListNode, buffer: *FreeListNode) void {
        if (prev) |p| {
            p.next = buffer.next;
        } else {
            self.head = buffer.next;
        }
    }
};
