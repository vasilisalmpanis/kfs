const printf = @import("debug").printf;
const PMM = @import("./pmm.zig").PMM;
const krn = @import("kernel");
const PAGE_OFFSET: u32 = 0xC0000000;
const PAGE_PRESENT: u8 = 0x1;
const PAGE_WRITE: u8 = 0x2;
const PAGE_USER: u8 = 0x4;
const PAGE_4MB: u8 = 0x80;

pub const PagingFlags = packed struct {
    present: bool       = true,
    writable: bool      = true,
    user: bool          = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool      = false,
    dirty: bool         = false,
    huge_page: bool     = false,
    global: bool        = false,
    available: u3       = 0x000, // available for us to use
};

pub extern var initial_page_dir: [1024]u32;
// const initial_page_dir: [*]u32 = @ptrFromInt(0xFFFFF000);

pub inline fn invalidatePage(page: usize) void {
    asm volatile ("invlpg (%eax)"
        :
        : [pg] "{eax}" (page),
    );
}

pub inline fn getCR0() u32 {
    return asm volatile (
        \\mov %cr0, %[value]
        : [value] "={eax}" (-> u32),
    );
}

pub inline fn getCR2() u32 {
    return asm volatile (
        \\mov %cr2, %[value]
        : [value] "={eax}" (-> u32),
    );
}

pub inline fn getCR3() u32 {
    return asm volatile (
        \\mov %cr3, %[value]
        : [value] "={eax}" (-> u32),
    );
}

const VmemBlock = struct {
    base: u32,
    size: u32,
    flags: u32
};

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

pub const VMM = struct {
    pmm: *PMM,

    pub fn init(pmm: *PMM) VMM {
        initial_page_dir[1023] = (@intFromPtr(&initial_page_dir) - PAGE_OFFSET)
            | PAGE_PRESENT | PAGE_WRITE;
        const vmm = VMM{ .pmm = pmm };
        return vmm;
    }

    pub fn pageTableToAddr(self: *VMM, pd_index: u32, pt_index: u32) u32 {
        _ = self;
        return ((pd_index << 22) | (pt_index << 12));
    }

    pub fn findFreeSpace(
        self: *VMM,
        num_pages: u32,
        from_addr: u32, // Should be 4Mb aligned
        to_addr: u32, // Should be 4Mb aligned
        user: bool
    ) u32 {
        var addr_to_ret: u32 = from_addr;
        var pages: u32 = 0;
        var pd_idx = from_addr >> 22;
        const max_pd_idx = to_addr >> 22;
        const pd: [*]PageEntry = @ptrFromInt(0xFFFFF000);
        while (pd_idx < max_pd_idx): (pd_idx += 1) {
            if (pd[pd_idx].present and pd[pd_idx].huge_page) {
                pages = 0;
                addr_to_ret = self.pageTableToAddr(pd_idx + 1, 0);
                continue ;
            }
            // Empty page dir entry
            if (!pd[pd_idx].present) {
                pages += 1024;
            } else if (pd[pd_idx].present and !pd[pd_idx].huge_page) {
                // If this page dir entry is not for userspace and we need for userspace => continue
                if (user and !pd[pd_idx].user) {
                    pages = 0;
                    addr_to_ret = self.pageTableToAddr(pd_idx + 1, 0);
                    continue ;
                }
                var pt_idx: u32 = 0;
                var pt: [*]PageEntry = @ptrFromInt(0xFFC00000);
                pt += (0x400 * pd_idx);
                while (pt_idx < 1024) : (pt_idx += 1) {
                    if (pt[pt_idx].present) {
                        pages = 0;
                        if (pt_idx < 1023) {
                            addr_to_ret = self.pageTableToAddr(
                                pd_idx,
                                pt_idx + 1
                            );
                        } else {
                            addr_to_ret = self.pageTableToAddr(
                                pd_idx + 1,
                                0
                            );
                        }
                        continue ;
                    }
                    pages += 1;
                    if (pages >= num_pages) {
                        return addr_to_ret;
                    }
                }
            }
            if (pages >= num_pages) {
                return addr_to_ret;
            }
        }
        return 0xFFFFFFFF;
    }

    pub fn findFreeAddr(self: *VMM) u32 {
        var pd_idx = PAGE_OFFSET >> 22;
        const pd: [*]u32 = @ptrFromInt(0xFFFFF000);
        var pt: [*]u32 = undefined;
        while (pd_idx < 1023) : (pd_idx += 1) {
            var pt_idx: u32 = 0;
            if (pd[pd_idx] == 0) {
                return pd_idx << 22;
            }
            if ((pd[pd_idx] & PAGE_4MB) == 0) {
                pt = @ptrFromInt(0xFFC00000);
                pt += (0x400 * pd_idx);
                while (pt_idx < 1023) {
                    if (pt[pt_idx] == 0) {
                        return self.pageTableToAddr(pd_idx, pt_idx);
                    }
                    pt_idx += 1;
                }
            }
        }
        return 0xFFFFFFFF;
    }

    pub fn unmapPage(self: *VMM, virt: u32) void {
        const pd_index = virt >> 22;
        const pt_index = (virt >> 12) & 0x3FF;
        var pt: [*]u32 = @ptrFromInt(0xFFC00000);
        pt += (0x400 * pd_index);
        const pfn: u32 = pt[pt_index] & 0xFFFFF000;
        self.pmm.freePage(pfn);
        pt[pt_index] = 0;
        invalidatePage(virt);
    }

    pub fn mapPage(
        self: *VMM,
        virtual_addr: u32,
        physical_addr: u32,
        flags: PagingFlags
    ) void {
        const pd_idx = virtual_addr >> 22;
        const pt_idx = (virtual_addr >> 12) & 0x3ff;
        const pd: [*]u32 = @ptrFromInt(0xFFFFF000);
        var pt: [*]u32 = undefined;

        if (pd[pd_idx] == 0) {
            const pt_pfn = self.pmm.allocPage();
            const tmp_pd_idx = (pt_pfn >> 20) / 4;
            pd[pd_idx] = pt_pfn | @as(u12, @bitCast(flags)) | PAGE_WRITE;
            const tmp = pd[tmp_pd_idx];
            pd[tmp_pd_idx] = PAGE_4MB | PAGE_WRITE | PAGE_PRESENT;
            pt = @ptrFromInt(0xFFC00000);
            pt += (0x400 * pd_idx);
            @memset(pt[0..1024], 0); // sets the whole PT to 0.
            pd[tmp_pd_idx] = tmp; // restore initial state of temp page dir
        }
        pt = @ptrFromInt(0xFFC00000);
        pt += (0x400 * pd_idx);
        if (pt[pt_idx] != 0)
            return; // Do something
        pt[pt_idx] = physical_addr | PAGE_PRESENT | PAGE_WRITE;
        const new_flags = @as(u12, @bitCast(flags));
        pt[pt_idx] = physical_addr | new_flags;
        invalidatePage(virtual_addr);
    }
};
