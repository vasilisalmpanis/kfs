const printf = @import("./printf.zig").printf;
const multiboot = @import("arch").multiboot;

const initial_page_dir: [*]u32 = @ptrFromInt(0xFFFFF000);

pub fn print_mmap(info: *multiboot.multiboot_info) void {
    var i: u32 = 0;
    printf("type\tmem region\t\tsize\n", .{});
    while (i < info.mmap_length) : (i += @sizeOf(multiboot.multiboot_memory_map)) {
        const mmap: *multiboot.multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        printf("{d}\t{x:0>8} {x:0>8}\t{d}\n", .{ mmap.type, mmap.addr[0], mmap.addr[0] + (mmap.len[0] - 1), mmap.len[0] });
    }
}

pub fn print_page_dir() void {
    var index: u32 = 0;
    printf("idx\t\tvirt\traw\t\tphys\t|pres|write|user|wr-th|cach|acc|dirt|4M|\n", .{});
    while (index < 1024) : (index += 1) {
        const entry = initial_page_dir[index];
        if (entry != 0) {
            const present = (entry & 1);
            const writable = (entry & 2);
            const user_accessible = (entry & 4);
            const write_through = (entry & (1 << 3));
            const cache_disabled = (entry & (1 << 4));
            const accessed = (entry & (1 << 5));
            const dirty = (entry & (1 << 6));
            const is_4mb_page = (entry & (1 << 7));
            const physical_frame = entry & 0xFFFFF000;

            printf("{d: >4}\t{x:0>8}\t{x:0>8}\t{x:0>8}\t|{}|{}|{}|{}|{}|{}|{}|{}|\n", .{
                index,
                index << 22,
                entry,
                physical_frame,
                present,
                writable,
                user_accessible,
                write_through,
                cache_disabled,
                accessed,
                dirty,
                is_4mb_page,
            });
        }
    }
}
