const lst = @import("../utils/list.zig");
const mm = @import("init.zig");
const arch = @import("arch");
const errors = @import("../syscalls/error-codes.zig");
const krn = @import("../main.zig");

const STACK_SIZE = mm.PAGE_SIZE * 2000;
const STACK_TOP = mm.PAGE_OFFSET;
const STACK_BOTTOM = STACK_TOP - STACK_SIZE;

pub const PROT_READ	 :u32 = 0x1;		// page can be read
pub const PROT_WRITE	 :u32 = 0x2;		// page can be written
pub const PROT_EXEC	 :u32 = 0x4;		// page can be executed
pub const PROT_SEM	 :u32 = 0x8;		// page may be used for atomic ops
pub const PROT_NONE	 :u32 = 0x0;		// page can not be accessed
pub const PROT_GROWSDOWN :u32 = 0x01000000;	// mprotect flag: extend change to start of growsdown vma
pub const PROT_GROWSUP   :u32 = 0x02000000;	// mprotect flag: extend change to end of growsup vma


pub const MAP_TYPE = enum(u4) {
    SHARED = 0x01,
    PRIVATE = 0x02,
    SHARED_VALIDATE = 0x03,
};

pub const MAP = packed struct(u32) {
        TYPE: MAP_TYPE,
        FIXED: bool = false,
        ANONYMOUS: bool = false,
        @"32BIT": bool = false,
        _7: u1 = 0,
        GROWSDOWN: bool = false,
        _9: u2 = 0,
        DENYWRITE: bool = false,
        EXECUTABLE: bool = false,
        LOCKED: bool = false,
        NORESERVE: bool = false,
        POPULATE: bool = false,
        NONBLOCK: bool = false,
        STACK: bool = false,
        HUGETLB: bool = false,
        SYNC: bool = false,
        FIXED_NOREPLACE: bool = false,
        _21: u5 = 0,
        UNINITIALIZED: bool = false,
        _: u5 = 0,
};

pub const VMA = struct {
    start: u32,
    end: u32,
    mm: ?*MM,
    flags: MAP,
    prot: u32,
    list: lst.ListHead,

    pub fn setup(self: *VMA, start: u32, end: u32, owner: ?*MM, flags: MAP, prot: u32) !void {
        self.start = start;
        self.end = end;
        self.mm = owner;
        self.flags = flags;
        self.prot = prot;
        self.list.setup();
        try self.allocFullVMA();
    }

    pub fn allocatePages(self: *VMA, start: u32, end: u32) !void {
        const num_of_pages = (end - start) / arch.PAGE_SIZE;
        for (0..num_of_pages) |index| {
            const page: u32 = krn.mm.virt_memory_manager.pmm.allocPage();
            if (page == 0) {
                for (0..index) |idx| {
                    mm.virt_memory_manager.unmapPage(start + idx * arch.PAGE_SIZE, true);
                }
                return error.OutOfMemory;
            }
            const flags = arch.vmm.PagingFlags{
                .writable = if (self.prot & PROT_WRITE > 0) true else false,
                .user = true,
                .present = true,
            };
            krn.mm.virt_memory_manager.mapPage(start + index * arch.PAGE_SIZE,
                page,
                flags
            );
        }
    }

    pub fn allocFullVMA(self: *VMA) !void {
        return try allocatePages(self, self.start, self.end);
    }

    pub fn new(addr: u32, end: u32, owner: *MM, flags: MAP, prot: u32) ?*VMA {
        const vma: ?*VMA = mm.kmalloc(VMA);
        if (vma) |_vma| {
            _vma.setup(addr, end, owner, flags, prot) catch {
                krn.mm.kfree(_vma);
                return null;
            };
        }
        return vma;
    }

    pub fn mergable(self: *VMA, addr: u32, length: u32, prot: u32, flags: MAP) bool {
        if (prot != self.prot)
            return false;
        if (self.flags.ANONYMOUS != flags.ANONYMOUS)
            return false;
        if (self.flags.TYPE != flags.TYPE)
            return false;
        if (addr + length == self.start)
            return true;
        if (addr == self.end)
            return true;
        return false;

        // TODO: File backed mappings.
    }
};

pub const MM = struct {
    stack_top: u32 = 0,     // Higher
    stack_bottom: u32 = 0,  // Lower
    code: u32 = 0,
    data: u32 = 0,
    bss: u32 = 0,
    heap: u32 = 0,
    vas: u32 = 0,
    vmas: ?*VMA = null,

    pub fn init() MM {
        return MM {
            .vas = 0,
            .bss = 0,
            .stack_top = STACK_TOP,
            .stack_bottom = STACK_BOTTOM,
            .vmas = null,
        };
    }

    pub fn new() ?*MM {
        const mmap: ?*MM = mm.kmalloc(MM);
        if (mmap) |_mmap| {
            _mmap.* = MM.init();
        }
        return mmap;
    }

    pub fn add_vma(
        self: *MM,
        curr: ?*lst.ListHead,
        addr: u32,
        length: u32,
        prot: u32,
        flags: MAP
    ) !?*VMA {
        var new_vma: ?*VMA = null;
        if (curr) |c| {
            const vma: *VMA = c.entry(VMA, "list");
            const prev = c.prev.?.entry(VMA, "list");
            const next = c.next.?.entry(VMA, "list");
            if (
                prev.start < vma.start
                and prev.mergable(addr, length, prot, flags)
            ) {
                try prev.allocatePages(prev.end, prev.end + length);
                prev.end += length;
                new_vma = prev;
                if (
                    next.start > vma.start
                    and next.mergable(addr, length, prot, flags)
                ) {
                    new_vma.?.end = next.end;
                    next.list.del();
                    krn.mm.kfree(next);
                }
                return new_vma;
            } else if (
                next.start > vma.start
                and next.mergable(addr, length, prot, flags)
            ) {
                try next.allocatePages(addr, next.start);
                next.start = addr;
                return next;
            } else if (vma.mergable(addr, length, prot, flags)) {
                if (vma.end == addr) {
                    try vma.allocatePages(vma.end, vma.end + length);
                    vma.end += length;
                } else {
                    try vma.allocatePages(addr, vma.start);
                    vma.start = addr;
                }
                return vma;
            }
        }
        new_vma = VMA.new(addr, addr + length, self, flags, prot);
        if (new_vma == null)
            return error.OutOfMemory;
        if (curr) |c| c.addTail(&new_vma.?.list);
        return new_vma;
    }

    pub fn mmap_area(self: *MM, addr: u32, length: u32, prot: u32, flags: MAP) i32
    {
        // 1. check if this addr is taken.
        //  - if free or map fixed, create mappings or replace mappings
        //  - if not free and map fixed replace
        //  - if not free and not map fixed, select random address.
        var hint: u32 = addr;
        var end = hint + length;
        var new_vma: ?*VMA = null;
        if (self.vmas) |list| {
            var it = list.list.iterator();
            while (it.next()) |node| {
                const vma: *VMA = node.curr.entry(VMA, "list");
                if (vma.end < hint)
                    continue;
                if (vma.start >= hint + length) {
                    new_vma = self.add_vma(
                        node.curr,
                        hint,
                        length,
                        prot,
                        flags
                    ) catch |err| switch (err) {
                        error.OutOfMemory => return -errors.ENOMEM
                    };
                    if (hint < self.vmas.?.start)
                        self.vmas = new_vma;
                    return @intCast(hint);
                }
                if (flags.FIXED == false) {
                    hint = vma.end;
                    end = hint + length;
                    continue;
                }
                // 1. begin before, end inside
                // 2. begin before, end after
                // 3. begin inside, end inside
                // 4. begin inside, end after
                // Implemente for FIXED
                // remap, or split mapping in two and remap etc.
            }
        }
        new_vma = self.add_vma(
            if (self.vmas == null) null else self.vmas.?.list.prev,
            hint,
            length,
            prot,
            flags
        ) catch |err| switch (err) {
            error.OutOfMemory => return -errors.ENOMEM
        };
        if (self.vmas == null or hint < self.vmas.?.start) {
            self.vmas = new_vma;
        }
        return @intCast(hint);
    }

    pub fn dup(self: *MM) ?*MM {
        const mmap: ?*MM = MM.new();
        if (mmap) |_mmap| {
            // TODO: Clone mappings.
            const vas: u32 = mm.virt_memory_manager.cloneVirtualSpace(); // it needs to take mappings into account
            if (vas == 0) {
                mm.kfree(_mmap);
                return null;
            }
            _mmap.vas = vas;
            _mmap.stack_top = self.stack_top;
            _mmap.stack_bottom = self.stack_bottom;
            _mmap.bss = self.bss;
            _mmap.code = self.code;
            _mmap.data = self.data;
            _mmap.heap = self.heap;
        }
        return mmap;
    }

    pub fn delete(self: *MM) void {
        if (self == &init_mm)
            return ;
        mm.virt_memory_manager.deinitVirtualSpace(self.vas);
        // TODO: free vmas
        mm.kfree(self);
    }
};

pub var init_mm: MM = MM.init();
