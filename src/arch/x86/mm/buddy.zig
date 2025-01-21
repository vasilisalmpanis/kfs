const std = @import("std");
const PAGE_SIZE = @import("memory.zig").PAGE_SIZE;

const MAX_ORDER: usize = 10;
const MAX_ORDER_SIZE: u32 = 1 << 10;

const FreeArea = struct {
    map: *u32,
    pfn: u32,
};

pub const BuddySystem = struct {
    free_area: [MAX_ORDER]std.SinglyLinkedList(FreeArea) = .{} ** MAX_ORDER,
    size: u64,
    begin: u32,
    // Initialize pub
    pub fn init(begin: u32, size: u64) *BuddySystem {
        var buddy: BuddySystem = BuddySystem{
            .size = size,
            .begin = begin,
        };
        var block: u32 = begin;
        while (block < begin + size) : (block += MAX_ORDER_SIZE * PAGE_SIZE) {
            buddy.free_area[MAX_ORDER - 1].prepend(.{FreeArea{
                .pfn = block,
                .map = undefined,
            }});
        }
        return &buddy;
    }

    // fn split_block(self: *BuddySystem, )

    //merge_blocks

    //alloc_pages -> takes order pub
    pub fn alloc_pages(self: *BuddySystem, order: u32) u32 {
        // 1: check in the free_area[order] and see
        // 2: if there are free blocks that occupy the request
        // 3: return address and mark it as used
        // 4: if not we need to split_block into lower order
        // 5: jmp 2
        // var pfn_addr: u32 = 0;
        var buf: self.free_area[order].Node = self.free_area[order];
        while (buf != null) : (buf = buf.next) {
            // if (buf)
        }
    }

    // free pages -> takes address pub

};

// TODO Map 16mb extra for the kernel to use in the PMM
