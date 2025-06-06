const printf = @import("debug").printf;
const PMM = @import("./pmm.zig").PMM;
const krn = @import("kernel");
const PAGE_SIZE = @import("./pmm.zig").PAGE_SIZE;
const PAGE_OFFSET: u32 = 0xC0000000;
const KERNEL_START: u32 = PAGE_OFFSET >> 22;
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
pub const current_page_dir: [*]PageEntry = @ptrFromInt(0xFFFFF000);
pub const first_page_table: [*]PageEntry = @ptrFromInt(0xFFC00000);

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

    inline fn erase(self: *PageEntry) void {
        const num: *u32 = @ptrCast(self);
        num.* = 0;
    }
};

pub const VMM = struct {
    pmm: *PMM,

    pub fn init(pmm: *PMM) VMM {
        initial_page_dir[1023] = (@intFromPtr(&initial_page_dir) - PAGE_OFFSET)
            | PAGE_PRESENT | PAGE_WRITE;
        var vmm = VMM{ 
            .pmm = pmm,
        };
        initial_page_dir[0] = 0;
        invalidatePage(0);
        vmm.initKernelSpace();
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
        while (pd_idx < max_pd_idx): (pd_idx += 1) {
            if (current_page_dir[pd_idx].present and current_page_dir[pd_idx].huge_page) {
                pages = 0;
                addr_to_ret = self.pageTableToAddr(pd_idx + 1, 0);
                continue ;
            }
            // Empty page dir entry
            if (!current_page_dir[pd_idx].present) {
                pages += 1024;
            } else if (current_page_dir[pd_idx].present and !current_page_dir[pd_idx].huge_page) {
                // If this page dir entry is not for userspace and we need for userspace => continue
                if (user and !current_page_dir[pd_idx].user) {
                    pages = 0;
                    addr_to_ret = self.pageTableToAddr(pd_idx + 1, 0);
                    continue ;
                }
                var pt_idx: u32 = 0;
                const pt: [*]PageEntry = first_page_table + (0x400 * pd_idx);
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
        while (pd_idx < 1023) : (pd_idx += 1) {
            var pt_idx: u32 = 0;
            if (current_page_dir[pd_idx] == 0) {
                return pd_idx << 22;
            }
            if ((current_page_dir[pd_idx].huge_page) == 0) {
                const pt: [*]PageEntry = first_page_table + (0x400 * pd_idx);
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

    pub fn unmapPage(self: *VMM, virt: u32, free_pfn: bool) void {
        const pd_index = virt >> 22;
        const pt_index = (virt >> 12) & 0x3FF;
        const pt: [*]PageEntry = first_page_table + (0x400 * pd_index);
        const pfn: u32 = pt[pt_index].address;
        if (free_pfn)
            self.pmm.freePage(pfn);
        pt[pt_index].erase();
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
        const pd: [*]u32 = @ptrCast(current_page_dir);
        var pt: [*]u32 = undefined;

        if (pd[pd_idx] == 0) {
            const pt_pfn = self.pmm.allocPage();
            pd[pd_idx] = pt_pfn | @as(u12, @bitCast(flags)) | PAGE_WRITE;
            pt = @ptrCast(first_page_table);
            pt += (0x400 * pd_idx);
            @memset(pt[0..1024], 0); // sets the whole PT to 0.
        }
        pt = @ptrCast(first_page_table);
        pt += (0x400 * pd_idx);
        if (pt[pt_idx] != 0)
            return; // Do something
        const new_flags = @as(u12, @bitCast(flags));
        pt[pt_idx] = physical_addr | new_flags;
        invalidatePage(virtual_addr);
    }

    fn allocatePageTable(self: *VMM, pd: [*]u32, pd_idx: u32, flags: PagingFlags) u32 {
        const new_page: u32 = self.pmm.allocPage();
        const current_pd: [*]u32 = @ptrCast(current_page_dir);
        var free_index: u32 = 0;
        while (free_index < 1024 and current_pd[free_index] != 0) : (free_index += 1) {} // TODO: improve
        if (free_index == 1024) {
            self.pmm.freePage(new_page);
            return 0;
        }
        current_pd[free_index] = new_page | PAGE_WRITE | PAGE_PRESENT;
        var pt: [*]u32 = @ptrCast(first_page_table);
        pt += (0x400 * free_index);
        invalidatePage(@intFromPtr(pt));
        pd[pd_idx] = new_page | @as(u12, @bitCast(flags));
        return free_index;
    }

    pub fn initKernelSpace(self: *VMM) void {
        const first_pt: [*]u32 = @ptrCast(first_page_table);
        for (KERNEL_START..1023) |idx| { // last one is kept for recursive paging
            if (initial_page_dir[idx] == 0) {
                const pfn: u32 = self.pmm.allocPage();
                if (pfn == 0) {
                    @panic("Could not allocate memory for kernel space.");
                }
                initial_page_dir[idx] = pfn | PAGE_PRESENT | PAGE_WRITE; // Premap page tables
                var pt = first_pt + (0x400 * idx);
                @memset(pt[0..1024], 0);
            }
        }
    }

    pub fn cloneTable(self: *VMM, pd_idx: u32, new_pd: [*]u32) u32 {
        const pd: [*]u32 = @ptrCast(current_page_dir);
        const flags: PagingFlags = @bitCast(@as(u12, @truncate(pd[pd_idx] & 0xFFF)));
        const free_index: u32 = self.allocatePageTable(new_pd, pd_idx, flags);
        if (free_index == 0)
            return 0;
        var temp_pt: [*]u32 = @ptrCast(first_page_table);
        temp_pt += 0x400 * free_index;
        var pt: [*]u32 = @ptrCast(first_page_table);
        pt += pd_idx * 0x400;
        for (0..1024) |idx| {
            if (pt[idx] != 0 and pt[idx] & PAGE_PRESENT != 0) {
                // allocate page
                const new_page: u32 = self.pmm.allocPage();
                if (new_page == 0) // TODO error
                    return 0;
                const virt = self.findFreeSpace(
                    1, PAGE_OFFSET, 0xFFFFF000, false
                );
                self.mapPage(virt, new_page, .{.writable = true, .present = true});
                const from_copy: [*] allowzero u8 = @ptrFromInt(self.pageTableToAddr(pd_idx, idx));
                const to_copy: [*] allowzero u8 = @ptrFromInt(virt);
                @memcpy(to_copy[0..PAGE_SIZE], from_copy[0..PAGE_SIZE]);
                const page_flags: u12 = @truncate(pt[idx] & 0xFFF);
                temp_pt[idx] = new_page | page_flags;
                self.unmapPage(virt, false);
            } else {
                temp_pt[idx] = 0;
            }
        }
        pd[free_index] = 0;
        return 1; 
    }

    pub fn cloneVirtualSpace(self: *VMM) u32 {
        const new_pd_addr = self.findFreeSpace(
            1, PAGE_OFFSET, 0xFFFFF000, false
        );
        const new_pd_ph_addr = self.pmm.allocPage();
        self.mapPage(new_pd_addr, new_pd_ph_addr, .{});
        const new_pd: [*]u32 = @ptrFromInt(new_pd_addr);
        // recursive mapping
        new_pd[1023] = new_pd_ph_addr | PAGE_PRESENT | PAGE_WRITE;
        
        const kernel_pd: u32 = PAGE_OFFSET >> 22;
        const pd: [*]u32 = @ptrCast(current_page_dir);
        for (kernel_pd..1023) |pd_idx| {
            // KERNEL_SPACE
            new_pd[pd_idx] = pd[pd_idx];
        }
        for (0..kernel_pd) |pd_idx| {
            // USER_SPACE
            if (pd[pd_idx] == 0) {
                continue ;
            }
            if (pd[pd_idx] & PAGE_4MB == 0) {
                _ = self.cloneTable(pd_idx, new_pd);
            } else {
                new_pd[pd_idx] = pd[pd_idx];
            }
        }
        self.unmapPage(new_pd_addr, false);
        return new_pd_ph_addr;
    }

    pub fn deinitVirtualSpace(self: *VMM, pd_phys: u32) void {
        if (pd_phys == @intFromPtr(&initial_page_dir) - PAGE_OFFSET)
            return ;

        const curr_phys_ps = asm volatile("mov %cr3, %[out]": [out] "=%{eax}" (-> u32));
        
        // Switch to page directory to clean, clean user space, return back to curr page directory
        asm volatile("mov %[pd], %cr3":: [pd] "r" (pd_phys));
        const kernel_pd: u32 = PAGE_OFFSET >> 22;
        var pd_idx: u32 = 0;
        while (pd_idx < kernel_pd) : (pd_idx += 1) {
            if (!current_page_dir[pd_idx].present) {
                continue ;
            }
            if (!current_page_dir[pd_idx].huge_page) {
                var pt: [*]PageEntry = @ptrCast(first_page_table);
                pt += pd_idx * 0x400;
                for (0..1024) |idx| {
                    self.pmm.freePage(pt[idx].address);
                    pt[idx].erase();
                }
                self.pmm.freePage(current_page_dir[pd_idx].address);
            } else {
                current_page_dir[pd_idx].erase();
            }
        }
        asm volatile("mov %[pd], %cr3":: [pd] "r" (curr_phys_ps));

        // Clean kernel space
        const old_pd_addr = self.findFreeSpace(
            1, PAGE_OFFSET, 0xFFFFF000, false
        );
        self.mapPage(old_pd_addr, pd_phys, .{});
        defer self.unmapPage(old_pd_addr, true);

        const old_pd: [*]u32 = @ptrFromInt(old_pd_addr);
        while (pd_idx < 1024) : (pd_idx += 1) {
            old_pd[pd_idx] = 0;
        }
    }
};
