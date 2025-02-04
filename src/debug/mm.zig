const printf = @import("./printf.zig").printf;
const multiboot = @import("arch").multiboot;
const mm = @import("kernel").mm;

const initial_page_dir: [*]u32 = @ptrFromInt(0xFFFFF000);

pub fn print_mmap(info: *multiboot.multiboot_info) void {
    var i: u32 = 0;
    printf("type\tmem region\t\tsize\n", .{});
    while (i < info.mmap_length) : (i += @sizeOf(multiboot.multiboot_memory_map)) {
        const mmap: *multiboot.multiboot_memory_map = @ptrFromInt(info.mmap_addr + i);
        printf("{d}\t{x:0>8} {x:0>8}\t{d}\n", .{
            mmap.type,
            mmap.addr[0],
            mmap.addr[0] + (mmap.len[0] - 1),
            mmap.len[0]
        });
    }
}

pub fn print_page_dir() void {
    var index: u32 = 0;
    printf(
        "idx\t\tvirt\traw\t\tphys\t|pres|write|user|wr-th|cach|acc|dirt|4M|\n",
        .{}
    );
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

            printf(
                "{d: >4}\t{x:0>8}\t{x:0>8}\t{x:0>8}\t|{}|{}|{}|{}|{}|{}|{}|{}|\n",
                .{
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
                }
            );
        }
    }
}

pub fn print_free_list() void {
    var buf = mm.kheap.head;
    printf("KHeap {?}\n", .{buf});
    while (buf != null) {
        printf("{x} - {x} {d}\n", .{
            @intFromPtr(buf),
            @intFromPtr(buf) + buf.?.block_size,
            buf.?.block_size}
        );
        buf = buf.?.next;
    }
    
    buf = mm.vheap.head;
    printf("VHeap {?}\n", .{buf});
    while (buf != null) {
        printf("{x} - {x} {d}\n", .{
            @intFromPtr(buf),
            @intFromPtr(buf) + buf.?.block_size,
            buf.?.block_size}
        );
        buf = buf.?.next;
    }
}

const PageEntry= packed struct {
    present: bool,
    writable: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    huge_page: bool,
    global: bool,
    available: u3,
    address: u20,
};

fn print_pe_format(pe: *const PageEntry) void {
    printf(" [", .{});
    if (pe.writable) printf("W", .{});
    if (pe.user) printf("U", .{});
    if (pe.write_through) printf("T", .{});
    if (pe.cache_disable) printf("C", .{});
    if (pe.accessed) printf("A", .{});
    if (pe.dirty) printf("D", .{});
    if (pe.global) printf("G", .{});
    printf("]\n", .{});
}

pub fn walkPageTables() void {
    var pd_idx: usize = 0;
    while (pd_idx < 1023) : (pd_idx += 1) {
        if (pd_idx > 900)
            continue;
        const pde: *PageEntry = @ptrCast(&initial_page_dir[pd_idx]);
        if (!pde.present) {
            continue;
        }
        const dir_base = pd_idx << 22;
        if (pde.huge_page) {
            const virt_addr: u32 = @intCast(dir_base);
            const phys_addr: u32 = @intCast(pde.address << 12);
            printf("{d: >4}      4MB: {x:0>8} {x:0>8} => {x:0>8} {x:0>8}",
                .{
                    pd_idx,
                    virt_addr, virt_addr + 4 * 1024 * 1024,
                    phys_addr, phys_addr + 4 * 1024 * 1024
                }
            );
            print_pe_format(pde);
            continue;
        }
        var page_table: [*]PageEntry = @ptrFromInt(0xFFC00000);
        page_table += (0x400 * pd_idx);
        var pt_idx: usize = 0;
        while (pt_idx < 1024) : (pt_idx += 1) {
            const pte = page_table[pt_idx];
            if (!pte.present) {
                continue;
            }
            const virt_addr = dir_base | (pt_idx << 12);
            var phys_addr: u32 = @intCast(pte.address);
            phys_addr <<= 12;
            printf("{d: >4} {d: >4} 4KB: {x:0>8} {x:0>8} => {x:0>8} {x:0>8}",
                .{
                    pd_idx,
                    pt_idx,
                    virt_addr, virt_addr + 4 * 1024,
                    phys_addr, phys_addr + 4 * 1024
                }
            );
            print_pe_format(&pte);
        }
    }
}
