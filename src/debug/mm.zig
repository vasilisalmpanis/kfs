const printf = @import("./printf.zig").printf;
const multiboot = @import("arch").multiboot;
const mm = @import("kernel").mm;

const initial_page_dir: [*]u32 = @ptrFromInt(0xFFFFF000);

pub fn printMmap(info: *multiboot.MultibootInfo) void {
    var i: u32 = 0;
    printf("type\tmem region\t\tsize\n", .{});
    while (i < info.mmap_length) : (i += @sizeOf(multiboot.MultibootMemoryMap)) {
        const mmap: *multiboot.MultibootMemoryMap = @ptrFromInt(info.mmap_addr + i);
        printf("{d}\t{x:0>8} {x:0>8}\t{d}\n", .{
            mmap.type,
            mmap.addr[0],
            mmap.addr[0] + (mmap.len[0] - 1),
            mmap.len[0]
        });
    }
}

pub fn printPageDir() void {
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

pub fn printFreeList() void {
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

fn printPEFormat(pe: *const PageEntry) void {
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
        if (pd_idx > 900 or (pd_idx >= 772 and pd_idx <= 775))
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
            printPEFormat(pde);
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
            printPEFormat(&pte);
        }
    }
}

fn printMappedArea(start: u32, end: u32, is_4mb: bool) void {
    const size = end - start;
    var size_friendly: u32 = size;
    var unit = "B ";
    if (size > 1024 * 1024 * 1024) {
        size_friendly = size / (1024 * 1024 * 1024);
        unit = "GB";
    } else if (size > 1024 * 1024) {
        size_friendly = size / (1024 * 1024);
        unit = "MB";
    } else if (size > 1024) {
        size_friendly = size / 1024;
        unit = "KB";
    }
    printf("{x:0>8} {x:0>8} {d:>4} {s} {d:>4} pgs {s:<16} {s}\n", .{
        start,
        end,
        size_friendly,
        unit,
        size / mm.PAGE_SIZE,
        switch (start) {
            0x00000000...0x00C00000 - 1 => "Kernel ID",
            0x00C00000...0xC0000000 - 1 => "User space",
            0xC0000000...0xC1000000 - 1 => "Kern code/stack",
            0xC1000000...0xFFFFF000 - 1 => "Kernel heap",
            0xFFFFF000...0xFFFFFFFF - 1 => "Recurs page dir",
            else => "Unknown"
        },

        if (is_4mb) "4M pages" else ""
    });
}

pub fn printMapped() void {
    var pd_idx: usize = 0;
    var start: u32 = 1;
    var end: u32 = 0;
    var huge_page: bool = false;
    var total: u32 = 0;
    while (pd_idx < 1024) : (pd_idx += 1) {
        const pde: *PageEntry = @ptrCast(&initial_page_dir[pd_idx]);
        if (!pde.present) {
            if (start != 1) {
                end = (pd_idx << 22);
                total += end - start;
                printMappedArea(start, end, huge_page);
                start = 1;
            }
            continue;
        }
        const dir_base = pd_idx << 22;
        if (start == 1) {
            start = dir_base;
            huge_page = pde.huge_page;
        } else if (huge_page != pde.huge_page) {
            end = (pd_idx << 22);
            total += end - start;
            printMappedArea(start, end, huge_page);
            start = dir_base;
            huge_page = pde.huge_page;
        }
        if (pde.huge_page) {
            continue;
        } else {
            var page_table: [*]PageEntry = @ptrFromInt(0xFFC00000);
            page_table += (0x400 * pd_idx);
            var pt_idx: usize = 0;
            while (pt_idx < 1024) : (pt_idx += 1) {
                const pte = page_table[pt_idx];
                if (!pte.present) {
                    if (start != 1) {
                        end = (pd_idx << 22) | (pt_idx << 12);
                        total += end - start;
                        printMappedArea(start, end, huge_page);
                        start = 1;
                    }
                    continue;
                }
                if (start == 1) {
                    start = dir_base | (pt_idx << 12);
                }
            }
        }
    }
    var size_friendly: u32 = total;
    var unit = "B ";
    if (total > 1024 * 1024 * 1024) {
        size_friendly = total / (1024 * 1024 * 1024);
        unit = "GB";
    } else if (total > 1024 * 1024) {
        size_friendly = total / (1024 * 1024);
        unit = "MB";
    } else if (total > 1024) {
        size_friendly = total / 1024;
        unit = "KB";
    }
    printf("Total: {d} {s} ({d} B)\n", .{size_friendly, unit, total});
}
