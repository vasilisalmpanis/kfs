const multiboot_info = @import("../boot/multiboot.zig").multiboot_info;
const multiboot_memory_map = @import("../boot/multiboot.zig").multiboot_memory_map;
const assert = @import("std").debug.assert;

pub const mm = struct {
    avail: u64,
    base: u32,
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
// };

pub const PAGE_SIZE: u32 = 4096;
pub var TOTAL_FRAMES: u32 = undefined;
pub var curr_frame: u32 = undefined;

pub fn mm_init(info: *multiboot_info) mm {
    var mm_avail: u64 = 0;
    var base: u32 = undefined;
    var i: u32 = 0;

    while (i < info.mmap_length) : (i += @sizeOf(multiboot_memory_map)) {
        const mmap: *multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        if (mmap.len[0] > 0 and mmap.type == 1) {
            mm_avail = mmap.len[0];
            base = mmap.addr[0];
            break;
        }
    }
    // Calculate the amount of physical available frames
    TOTAL_FRAMES = @intCast((mm_avail / @as(u64, PAGE_SIZE)));
    base += 4095;
    if ((base % PAGE_SIZE) > 0) {
        mm_avail = mm_avail - (base & 0xfff);
        base = (base & 0xfffff000) + PAGE_SIZE;
    }
    curr_frame = base;
    // const temporary: temp = temp{ .val = 1, .list = .{ .prev = undefined, .next = undefined } };
    // const afteroff = containerOf(temp, "list", &temporary.list);
    // assert(@TypeOf(temporary) == @TypeOf(afteroff.*));
    // return mm{ .avail = mm_avail, .base = base };
}

// create page

// get page
