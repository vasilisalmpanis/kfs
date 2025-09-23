const printf = @import("debug").printf;
const PMM = @import("./pmm.zig").PMM;
const krn = @import("kernel");
const std = @import("std");
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

pub const VASpair = struct {
    virt: u32 = 0,
    phys: u32 = 0,
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
        const pfn: u32 = pt[pt_index].address << 12;
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

    pub fn mapPageTable(self: *VMM, pd: [*]u32, pd_idx: u32, flags: PagingFlags, pt_phys: u32) !u32 {
        const current_pd: [*]u32 = @ptrCast(current_page_dir);
        var free_index: u32 = 0;
        while (free_index < 1024 and current_pd[free_index] != 0) : (free_index += 1) {} // TODO: improve
        if (free_index == 1024) {
            self.pmm.freePage(pt_phys);
            return krn.errors.PosixError.ENOMEM;
        }
        current_pd[free_index] = pt_phys | PAGE_WRITE | PAGE_PRESENT;
        var pt: [*]u32 = @ptrCast(first_page_table);
        pt += (0x400 * free_index);
        invalidatePage(@intFromPtr(pt));
        pd[pd_idx] = pt_phys | @as(u12, @bitCast(flags));
        return free_index;
    }

    fn allocatePageTable(self: *VMM, pd: [*]u32, pd_idx: u32, flags: PagingFlags) !u32 {
        const new_page: u32 = self.pmm.allocPage();
        return try self.mapPageTable(pd, pd_idx, flags, new_page);
    }

    pub fn newVAS(self: *VMM) !VASpair{
        const new_pd_ph_addr = self.pmm.allocPage();
        const new_pair = self.mapVAS(new_pd_ph_addr);
        const new_pd: [*]u32 = @ptrFromInt(new_pair.virt);
        @memset(new_pd[0..1024], 0);
        // recursive mapping
        new_pd[1023] = new_pd_ph_addr | PAGE_PRESENT | PAGE_WRITE;

        const kernel_pd: u32 = PAGE_OFFSET >> 22;
        const pd: [*]u32 = @ptrCast(current_page_dir);

        // KERNEL_SPACE
        for (kernel_pd..1023) |pd_idx| {
            new_pd[pd_idx] = pd[pd_idx];
        }
        return new_pair;
    }

    pub fn mapVAS(self: *VMM, phys: u32) VASpair {
        const virt = self.findFreeSpace(
            1, PAGE_OFFSET, 0xFFFFF000, false
        );
        self.mapPage(virt, phys, .{});
        return VASpair{
            .virt = virt,
            .phys = phys,
        };
    }

    pub fn unmapVAS(self: *VMM, pair: VASpair) void {
        self.unmapPage(pair.virt, false);
    }

    pub fn dupPage(self: *VMM, old_pt: [*]u32, new_pt: [*]u32, pd_idx:u32, pt_idx: u32) !void {
        const new_page: u32 = self.pmm.allocPage();
        if (new_page == 0) // TODO error
            return krn.errors.PosixError.ENOMEM;
        const virt = self.findFreeSpace(
            1, PAGE_OFFSET, 0xFFFFF000, false
        );
        self.mapPage(virt, new_page, .{.writable = true, .present = true});
        const from_copy: [*] allowzero u8 = @ptrFromInt(self.pageTableToAddr(pd_idx, pt_idx));
        const to_copy: [*] allowzero u8 = @ptrFromInt(virt);
        @memcpy(to_copy[0..PAGE_SIZE], from_copy[0..PAGE_SIZE]);
        const page_flags: u12 = @truncate(old_pt[pt_idx] & 0xFFF);
        new_pt[pt_idx] = new_page | page_flags;
        self.unmapPage(virt, false);
    }

    pub fn dupArea(self: *VMM, start: u32, end: u32, pair: VASpair, area_type: krn.mm.MAP_TYPE) !void{
        // We assume that start and end are page aligned (we should check though)
        const pd: [*]u32 = @ptrCast(current_page_dir);
        const new_pd: [*]u32 = @ptrFromInt(pair.virt);

        // Calculate page-aligned boundaries for exclusive end
        const last_addr = if (end > 0) end - 1 else 0;

        // PD
        const pd_start_idx: u32 = start >> 22;
        const pd_end_idx: u32 = last_addr >> 22;

        // PT
        var pt_start_idx: u32 = (start >> 12) & 0x3FF;
        const pt_end_idx: u32 = ((last_addr >> 12) & 0x3FF) + 1; // +1 for exclusive range

        const kernel_pd: u32 = PAGE_OFFSET >> 22;

        for (pd_start_idx..pd_end_idx + 1) |pd_idx| {
            if (pd_idx >= kernel_pd)
                return ;
            const pt_end: u32 = if (pd_idx == pd_end_idx) pt_end_idx else 1024;

            // Add range validation to prevent integer overflow
            if (pt_start_idx >= pt_end) {
                @panic("VMM.dupArea() pt_start_idx >= pt_end!");
            }

            // Either allocate or map the already existing page table
            var temp_idx: u32 = undefined;
            const flags: PagingFlags = @bitCast(@as(u12, @truncate(pd[pd_idx] & 0xFFF)));
            if (new_pd[pd_idx] == 0) {
                temp_idx = try self.allocatePageTable(new_pd, pd_idx, flags);
            } else {
                temp_idx = try self.mapPageTable(new_pd,
                    pd_idx,
                    flags,
                    (new_pd[pd_idx] >> 12) << 12,
                );
            }

            // Copy the values of old page table to new
            var old_pt: [*]u32 = @ptrCast(first_page_table);
            old_pt += 0x400 * pd_idx;
            var new_pt: [*]u32 = @ptrCast(first_page_table);
            new_pt += 0x400 * temp_idx;
            for (pt_start_idx .. pt_end) |pt_idx| {
                if (old_pt[pt_idx] == 0)
                    @panic("VMM: cloning 0. This shouldn't happen\n");
                switch (area_type) {
                    .PRIVATE => {
                        try self.dupPage(old_pt, new_pt, pd_idx, pt_idx);
                    },
                    .SHARED, .SHARED_VALIDATE => {
                        new_pt[pt_idx] = old_pt[pt_idx];
                    }
                }
            }
            pt_start_idx = 0;
            pd[temp_idx] = 0;
        }
    }

    pub fn releaseArea(self: *VMM, start: u32, end: u32, area_type: krn.mm.MAP_TYPE) void {
        if (area_type == .SHARED) {
            krn.logger.INFO("We should somehow refcount pages and only free when the last user frees\n", .{});
            return;
        }
        const pd: [*]u32 = @ptrCast(current_page_dir);

        // Calculate page-aligned boundaries for exclusive end
        // end is exclusive, so we need the last page that should be freed
        const last_addr = if (end > 0) end - 1 else 0;
        
        const pd_start_idx: u32 = start >> 22;
        const pd_end_idx: u32 = last_addr >> 22;

        const kernel_pd: u32 = PAGE_OFFSET >> 22;
        const safe_pd_end_idx = @min(pd_end_idx, kernel_pd - 1);

        if (pd_start_idx >= kernel_pd) {
            krn.logger.WARN("Attempted to free kernel space area {x}-{x}, ignoring", .{start, end});
            return;
        }
        // PT indexes
        var pt_start_idx: u32 = (start >> 12) & 0x3FF;
        const pt_end_idx: u32 = ((last_addr >> 12) & 0x3FF) + 1; // +1 for exclusive range

        for (pd_start_idx..safe_pd_end_idx + 1) |pd_idx| {
            const pt_end: u32 = if (pd_idx == safe_pd_end_idx) pt_end_idx else 1024;

            if (pd[pd_idx] == 0) {
                pt_start_idx = 0;
                continue;
            }

            var pt: [*]u32 = @ptrCast(first_page_table);
            pt += 0x400 * pd_idx;

            if (pt_start_idx >= pt_end) {
                @panic("VMM.releaseArea() pt_start_idx >= pt_end!");
            }

            for (pt_start_idx .. pt_end) |pt_idx| {
                if (pt[pt_idx] != 0) {
                    const phys: u32 = (pt[pt_idx] >> 12) << 12;
                    self.pmm.freePage(phys);
                    pt[pt_idx] = 0; // Clear the PTE
                }
            }
            if (std.mem.allEqual(u32, pt[0..1024], 0)) {
                self.pmm.freePage((pd[pd_idx] >> 12) << 12);
                pd[pd_idx] = 0;
                invalidatePage(
                    self.pageTableToAddr(pd_idx, 0)
                );
            }

            pt_start_idx = 0;
        }
    }
};
