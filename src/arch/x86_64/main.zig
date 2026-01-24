const std = @import("std");
const krn = @import("kernel");

pub const io = struct {
    pub export fn inb(_: u16) u8 {
        return 0;
    }

    pub export fn inw(_: u16) u16 {
        return 0;
    }

    pub export fn inl(_: u16) u32 {
        return 0;
    }

    pub export fn outb(_: u16, _: u8) void {
    }

    pub export fn outw(_: u16, _: u16) void {
    }

    pub export fn outl(_: u16, _: usize) void {
    }
};

pub const system = struct {
    pub fn halt() noreturn {
        while (true) {}
    }

    pub fn enableWriteProtect() void {
    }
};

pub const gdt = struct {
    pub fn gdtInit() void {}
};

pub const multiboot = struct {
    pub const Header = struct {
        total_size: u32, 
        reserved: u32,
    };

    pub const Tag = struct {
        type: u32, 
        size: u32,
    };

    pub const MemMapEntry = struct {
        base_addr: u64,
        length: u64,
        type: u32,
        reserved: u32,
    };

    pub const TagMemoryMap = struct{
        type: u32 = 6,
        size: u32,
        entry_size: u32,
        entry_version: u32,

        pub fn getMemMapEntries(_: *TagMemoryMap) [*]MemMapEntry {
            return @ptrFromInt(0xA000_0000);
        }
    };

    pub const TagFrameBufferInfo = struct{
        type: u32 = 8,
        size: u32,
        addr: u64,
        pitch: u32,
        width: u32,
        height: u32,
        bpp: u8,
        fb_type: u8,
        reserved: u8,
    };

    pub const TagELFSymbols = struct{
        type: u32 = 9,
        size: u32,
        num: u16,
        entsize: u16,
        shndx: u16,
        reserved: u16,

        pub fn getSectionHeaders(_: *TagELFSymbols) [*]std.elf.Elf32_Shdr {
            return @ptrFromInt(0xA000_0000);
        }
    };

    pub const Multiboot = struct {
        addr: usize,
        header: *Header,
        curr_tag: ?*Tag = null,
        tag_addresses: [22]u32 = .{0} ** 22,
        
        pub fn init(addr: usize) Multiboot {
            return Multiboot{
                .addr = addr,
                .header = @ptrFromInt(addr),
            };
        }

        pub fn nextTag(self: *Multiboot) ?*Tag {
            return self.curr_tag;
        }

        pub fn getTag(_: *Multiboot, comptime T: type) ?*T {
            return null;
        }
        pub fn relocate(_: *Multiboot, _: usize) usize{
            return 0;
        }
    };
};

pub const vmm = struct {
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
    pub const VMM = struct {
        pmm: *pmm.PMM,
        pub fn findFreeSpace(self: *VMM, num_pages: usize, from_addr: usize, to_addr: usize, user: bool) usize {
            _ = self;
            _ = num_pages;
            _ = from_addr;
            _ = to_addr;
            _ = user;
            return 0;
        }

        pub fn mapPage(_: *VMM, _: usize, _: usize, _: PagingFlags) void {}
        pub fn unmapPage(_: *VMM, _: usize, _: bool) void {}
        pub fn releaseArea(_: *VMM, _: usize, _: usize, _: krn.mm.MAP_TYPE) void {}
        pub fn init(_pmm: *pmm.PMM) VMM{
            return VMM{
                .pmm = _pmm
            };
        }
    };

    pub const initial_page_dir: usize = 1000;
};

pub const pmm = struct {
    pub const PMM = struct {
        pub fn init(_: usize, _: usize) PMM {
            return PMM{};
        }
        pub fn allocPage(_: *PMM) usize {
            return 0;
        }
        pub fn allocPages(_: *PMM, _: usize) usize {
            return 0;
        }
        pub fn freePage(_: *PMM, _: usize) void {}
    };
};

pub const idt = struct {
    pub fn idtInit() void {}
    pub const KERNEL_CODE_SEGMENT = 0;
    pub const KERNEL_DATA_SEGMENT = 0;
    pub fn switchTo(_: *krn.task.Task, _: *krn.task.Task, _: *Regs) *Regs{
        return &krn.task.initial_task.regs;
    }
    pub fn goUserspace() void {}
};

pub const Regs = struct {
    pub fn init() Regs {
        return Regs{};
    }
    pub fn setStackPointer(_: *Regs, _: usize) void {
    }
};

pub const cpu = struct {
    pub fn disableInterrupts() void {}
    pub fn enableInterrupts() void {}
    pub fn getStackFrameAddr() usize {
        return 0;
    }
};

pub const syscalls = struct {
    pub fn initSyscalls() void {}
};

pub fn archReschedule() void {

}

pub fn setupStack(_: usize, _: usize, _: usize, _: usize, _: usize) usize {
    return 0;
}

pub fn pageAlign(addr: usize, _: bool) usize {
    return addr;
}

pub fn isPageAligned(_: usize) bool {
    return true;
}

pub const PAGE_SIZE = 4096;
pub const IDT_MAX_DESCRIPTORS = 256;
pub const CPU_EXCEPTION_COUNT = 32;
pub const SYSCALL_INTERRUPT = 0x80;
