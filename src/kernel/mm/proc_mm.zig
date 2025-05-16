const lst = @import("../utils/list.zig");
const mm = @import("init.zig");

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

const VMA = struct {
    start: u32,
    end: u32,
    mm: ?*MM,
    flags: u32,
    list: lst.ListHead,
};

pub const MM = struct {
    stack_top: u32 = 0,     // Higher
    stack_bottom: u32 = 0,  // Lower
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

