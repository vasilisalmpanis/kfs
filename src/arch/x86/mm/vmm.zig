const printf = @import("drivers").printf;
const PMM = @import("./pmm.zig").PMM;

const PAGE_PRESENT: u8 = 0x1;
const PAGE_WRITE: u8 = 0x2;
const PAGE_4MB: u8 = 0x80;

// extern var initial_page_dir: [1024]u32;
const initial_page_dir: [*]u32 = @ptrFromInt(0xFFFFF000);

fn print_page_dir() void {
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

pub fn print_page_table(virtual_addr: u32) void {
    const pd_index = virtual_addr >> 22; // Page directory index
    const page_table_addr = initial_page_dir[pd_index] & 0xFFFFF000;

    if (page_table_addr == 0) {
        printf("No page table exists for address 0x{x}\n", .{virtual_addr});
        return;
    }

    const page_table: [*]u32 = @ptrFromInt(page_table_addr);

    printf("Page Table for Address 0x{x} (Page Directory Index: {d}):\n", .{ virtual_addr, pd_index });

    for (0..1024) |i| {
        if (page_table[i] != 0) {
            const flags = page_table[i] & 0xFFF;
            printf("  Entry {d}: Physical Addr: 0x{x}, Flags:\n", .{ i, page_table[i] & 0xFFFFF000 });

            printf("    Present:       {s}\n", .{if (flags & 1 != 0) "Yes" else "No"});
            printf("    Writable:      {s}\n", .{if (flags & 2 != 0) "Yes" else "No"});
            printf("    User/Supervisor: {s}\n", .{if (flags & 4 != 0) "User" else "Supervisor"});
            printf("    Write-Through:  {s}\n", .{if (flags & 8 != 0) "Enabled" else "Disabled"});
            printf("    Cache Disabled: {s}\n", .{if (flags & 16 != 0) "Yes" else "No"});
            printf("    Accessed:      {s}\n", .{if (flags & 32 != 0) "Yes" else "No"});
            printf("    Dirty:         {s}\n", .{if (flags & 64 != 0) "Yes" else "No"});
            printf("    Page Size:     {s}\n", .{if (flags & 128 != 0) "4MB" else "4KB"});
        }
    }
}

pub inline fn InvalidatePage(page: usize) void {
    asm volatile ("invlpg (%eax)"
        :
        : [pg] "{eax}" (page),
    );
}

pub const VMM = struct {
    pmm: *PMM,

    pub fn init(pmm: *PMM) VMM {
        const vmm = VMM{ .pmm = pmm };
        return vmm;
    }

    // pub fn alloc(size: u32) u32 {

    // }

    // pub fn free(v_addr: u32) void {

    // }

    pub fn map_page(self: *VMM, virtual_addr: u32, physical_addr: u32) void {
        const pd_idx = virtual_addr >> 22;
        const pt_idx = (virtual_addr >> 12) & 0x3ff;
        const pd: [*]u32 = @ptrFromInt(0xFFFFF000);
        var pt: [*]u32 = undefined;

        if (pd[pd_idx] == 0) {
            const pt_pfn = self.pmm.alloc_page();
            const tmp_pd_idx = (pt_pfn >> 20) / 4;
            pd[pd_idx] = pt_pfn | 3; // Present + writable
            const tmp = pd[tmp_pd_idx];
            pd[tmp_pd_idx] = PAGE_4MB | PAGE_WRITE | PAGE_PRESENT;
            pt = @ptrFromInt(0xFFC00000);
            pt += (0x400 * pd_idx);
            @memset(pt[0..1024], 0);
            pd[tmp_pd_idx] = tmp; // restore initial state of temp page dir
        }
        pt = @ptrFromInt(0xFFC00000);
        pt += (0x400 * pd_idx);
        if (pt[pt_idx] != 0)
            return; // Do something
        pt[pt_idx] = physical_addr | 0x3;
        InvalidatePage(virtual_addr);
    }
};

// Page Directory Entry Structure
// |00000000|00R00000|000PAAAG|PDAPPURP|

// Virtual addr: 0xdd000000
// |11011101|00000000|00000000|00000000|
// PDE Index: 0xdd000000 >> 22 = 884
// PTE Index: (0xdd000000 >> 12) & 0x3ff = 0
// Page offset: 0xdd000000 & 0xfff = 0
