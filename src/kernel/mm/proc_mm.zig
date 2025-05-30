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

const VMA = struct {
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
        try self.allocatePages();
    }

    pub fn allocatePages(self: *VMA) !void {
        const num_of_pages = (self.end - self.start) / arch.PAGE_SIZE;
        for (0..num_of_pages) |index| {
            const page: u32 = krn.mm.virt_memory_manager.pmm.allocPage();
            if (page == 0) {
                for (0..index) |idx| {
                    mm.virt_memory_manager.unmapPage(self.start + idx * arch.PAGE_SIZE, true);
                }
                return error.OutOfMemory;
            }
            const flags = arch.vmm.PagingFlags{
                .writable = if (self.prot & PROT_WRITE > 0) true else false,
                .user = true,
                .present = true,
            };
            krn.mm.virt_memory_manager.mapPage(self.start + index * arch.PAGE_SIZE,
                page,
                flags
            );
        }
    }
};

pub const MM = struct {
    stack_top: u32 = 0,     // Higher
    stack_bottom: u32 = 0,  // Lower
    code: u32 = 0,
    heap: u32 = 0,
    bss: u32 = 0,
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
        const num: u32 = mm.kmalloc(@sizeOf(MM));
        if (num == 0)
            return null;
        const mmap: *MM = @ptrFromInt(num);
        mmap.* = MM.init();
        return @ptrFromInt(num);
    }

    pub fn mmap_area(self: *MM, addr: u32, length: u32, prot: u32, flags: MAP) i32
    {
        // 1. check if this addr is taken.
        //  - if free or map fixed, create mappings or replace mappings
        //  - if not free and map fixed replace
        //  - if not free and not map fixed, select random address.
        const end = arch.pageAlign(addr + length, false);
        if (self.vmas) |list| {
            var it = list.list.iterator();
            while (it.next()) |node| {
                const vma: *VMA = node.curr.entry(VMA, "list");
                _ = vma;
            }
        } else {
            const new_map: u32 = mm.kmalloc(@sizeOf(VMA));
            if (new_map == 0) {
                return -errors.ENOMEM;
            }
            const mapping: *VMA = @ptrFromInt(new_map);
            mapping.setup(addr, end, self, flags, prot) catch {
                krn.mm.kfree(new_map);
                return -errors.ENOMEM;
            };
            self.vmas = mapping;
            return @intCast(mapping.start);
            // allocate physical pages.
        }
        return 0;
    }

    pub fn dup(self: *MM) ?*MM {
        const mmap: ?*MM = MM.new();
        if (mmap) |_mmap| {
            // TODO: Clone mappings.
            const vas: u32 = mm.virt_memory_manager.cloneVirtualSpace(); // it needs to take mappings into account
            if (vas == 0) {
                mm.kfree(@intFromPtr(_mmap));
                return null;
            }
            _mmap.vas = vas;
            _mmap.stack_top = self.stack_top;
            _mmap.stack_bottom = self.stack_bottom;
            _mmap.bss = self.bss;

        }
        return mmap;
    }

    pub fn delete(self: *MM) void {
        if (self == &init_mm)
            return ;
        mm.virt_memory_manager.deinitVirtualSpace(self.vas);
        // TODO: free vmas
        mm.kfree(@intFromPtr(self));
    }
};

pub var init_mm: MM = MM.init();

