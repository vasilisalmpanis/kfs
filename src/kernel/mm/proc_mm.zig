const lst = @import("../utils/list.zig");
const mm = @import("init.zig");
const arch = @import("arch");
const errors = @import("../syscalls/error-codes.zig").PosixError;
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
        _32BIT: bool = false,
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

        pub fn anonymous() MAP{
            return MAP{
                .TYPE = .PRIVATE,
                .ANONYMOUS = true,
            };
        }
};

pub const VMA = struct {
    start: usize,
    end: usize,
    mm: ?*MM,
    flags: MAP,
    prot: u32,
    file: ?*krn.fs.File,
    offset: usize,
    list: lst.ListHead,

    pub fn setup(self: *VMA, start: usize, end: usize, owner: ?*MM, flags: MAP, prot: u32) !void {
        self.start = start;
        self.end = end;
        self.mm = owner;
        self.flags = flags;
        self.prot = prot;
        self.list.setup();
        self.file = null;
        self.offset = 0;
        try self.allocFullVMA();
    }

    pub fn dup(self: *VMA, other: *VMA, pair: krn.mm.VASpair) !void{
        try mm.virt_memory_manager.dupArea(self.start, self.end, pair, self.flags.TYPE);
        other.start = self.start;
        other.end = self.end;
        other.flags = self.flags;
        other.prot = self.prot;
    }

    pub fn allocatePages(self: *VMA, start: usize, end: usize) !void {
        const num_of_pages = (end - start) / arch.PAGE_SIZE;
        for (0..num_of_pages) |index| {
            const page: usize = krn.mm.virt_memory_manager.pmm.allocPage();
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
            const virt_addr: usize = start + index * arch.PAGE_SIZE;
            krn.mm.virt_memory_manager.mapPage(virt_addr,
                page,
                flags
            );
            const page_buf: [*]usize = @ptrFromInt(virt_addr);
            @memset(page_buf[0..1024], 0);
        }
    }

    pub fn allocFullVMA(self: *VMA) !void {
        return try allocatePages(self, self.start, self.end);
    }

    pub fn new(
        addr: usize,
        end: usize,
        owner: *MM,
        flags: MAP,
        prot: u32,
        file: ?*krn.fs.File,
        offset: usize,
    ) ?*VMA {
        const vma: ?*VMA = mm.kmalloc(VMA);
        if (vma) |_vma| {
            _vma.setup(addr, end, owner, flags, prot) catch {
                krn.mm.kfree(_vma);
                return null;
            };
            _vma.file = file;
            _vma.offset = offset;
            if (file) |_file| {
                _file.ref.ref();
                defer _file.ref.unref();
                const old_pos = _file.pos;
                _file.pos = offset;
                const buffer: [*]u8 = @ptrFromInt(_vma.start);

                var read: usize = 0;
                while (read < _vma.end - _vma.start) {
                    const ret = _file.ops.read(_file, @ptrCast(&buffer[read]), _vma.end - _vma.start - read) catch {
                        mm.virt_memory_manager.releaseArea(_vma.start, _vma.end, _vma.flags.TYPE);
                        krn.mm.kfree(_vma);
                        return null;
                    };
                    if (ret == 0)
                        break;
                    read += ret;
                }
                _file.pos = old_pos;
            }
        }
        return vma;
    }

    pub fn allocEmpty() ?*VMA {
        const vma: ?*VMA = mm.kmalloc(VMA);
        if (vma) |_vma| {
            _vma.mm = null;
            _vma.start = 0;
            _vma.end = 0;
            _vma.list = krn.list.ListHead.init();
            _vma.list.setup();
            _vma.prot = 0;
            _vma.flags = undefined;
        }
        return vma;
    }

    pub fn mergable(self: *VMA, addr: usize, length: usize, prot: u32, flags: MAP) bool {
        if (prot != self.prot)
            return false;
        if (self.flags.ANONYMOUS != flags.ANONYMOUS)
            return false;
        if (self.flags.TYPE != flags.TYPE)
            return false;
        if (self.file != null)
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
    stack_top: usize = 0,     // Higher
    stack_bottom: usize = 0,  // Lower
    code: usize = 0,
    data: usize = 0,
    arg_start: usize = 0, // Addres to begin of args strings
    arg_end: usize = 0,
    argc: usize = 0, // address
    env_start: usize = 0,
    env_end: usize = 0,
    bss: usize = 0,
    heap: usize = 0,
    brk_start: usize = 0,
    brk: usize = 0,
    vas: usize = 0,
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
        addr: usize,
        length: usize,
        prot: u32,
        flags: MAP,
        file: ?*krn.fs.File,
        offset: usize,
    ) !?*VMA {
        var new_vma: ?*VMA = null;
        if (file == null) {
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
        }
        new_vma = VMA.new(
            addr,
            addr + length,
            self, flags,
            prot,
            file,
            offset
        );
        if (new_vma == null)
            return error.OutOfMemory;
        if (curr) |c| c.addTail(&new_vma.?.list);
        return new_vma;
    }

    pub fn mmap_area(
        self: *MM,
        addr: usize,
        length: usize,
        prot: u32,
        flags: MAP,
        file: ?*krn.fs.File,
        offset: usize,
    ) !usize
    {
        // 1. check if this addr is taken.
        //  - if free or map fixed, create mappings or replace mappings
        //  - if not free and map fixed replace
        //  - if not free and not map fixed, select random address.
        var hint: usize = addr;
        var end = hint + length;
        var new_vma: ?*VMA = null;
        
        if (flags.FIXED) {            
            _ = krn.do_munmap(
                self, @intCast(hint),
                @intCast(end)
            ) catch {};
            
            new_vma = try self.add_vma(
                if (self.vmas == null) null else self.findInsertPoint(hint),
                hint,
                length,
                prot,
                flags,
                file,
                offset
            );
            if (self.vmas == null or hint < self.vmas.?.start)
                self.vmas = new_vma;
            krn.logger.DEBUG(
                "[PID {d}] mmap done 0x{x:0>8} - 0x{x:0>8}\n", 
                .{krn.task.current.pid, hint, end}
            );
            return @intCast(hint);
        }
        if (self.vmas) |list| {
            var it = list.list.iterator();
            while (it.next()) |node| {
                const vma: *VMA = node.curr.entry(VMA, "list");
                if (vma.end <= hint)
                    continue;
                if (vma.start >= hint + length) {
                    new_vma = self.add_vma(
                        node.curr,
                        hint,
                        length,
                        prot,
                        flags,
                        file,
                        offset
                    ) catch |err| switch (err) {
                        error.OutOfMemory => return errors.ENOMEM
                    };
                    if (hint < self.vmas.?.start)
                        self.vmas = new_vma;        
                    krn.logger.DEBUG(
                        "[PID {d}] mmap done 0x{x:0>8} - 0x{x:0>8}\n", 
                        .{krn.task.current.pid, hint, end}
                    );
                    return @intCast(hint);
                }
                hint = vma.end;
                end = hint + length;
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
            flags,
            file,
            offset
        ) catch |err| switch (err) {
            error.OutOfMemory => return errors.ENOMEM
        };
        if (self.vmas == null or hint < self.vmas.?.start) {
            self.vmas = new_vma;
        }
        krn.logger.DEBUG(
            "[PID {d}] mmap done 0x{x:0>8} - 0x{x:0>8}\n", 
            .{krn.task.current.pid, hint, end}
        );
        return @intCast(hint);
    }
    
    fn findInsertPoint(self: *MM, addr: usize) ?*krn.list.ListHead {
        if (self.vmas) |list| {
            var it = list.list.iterator();
            while (it.next()) |node| {
                const vma: *VMA = node.curr.entry(VMA, "list");
                if (vma.start > addr)
                    return node.curr;
            }
            return self.vmas.?.list.prev;
        }
        return null;
    }

    pub fn dup(self: *MM) ?*MM {
        const mmap: ?*MM = MM.new();
        if (mmap) |_mmap| {
            const vas_pair: krn.mm.VASpair = mm.virt_memory_manager.newVAS() catch {
                return null;
            };
            defer mm.virt_memory_manager.unmapPage(vas_pair.virt, false);
            _mmap.vas = vas_pair.phys;
            if (_mmap.vas == 0) {
                mm.kfree(_mmap);
                return null;
            }
            if (self.vmas) |head| {
                var it = head.list.iterator();
                while (it.next()) |entry| {
                    const vma = entry.curr.entry(VMA, "list");
                    if (VMA.allocEmpty()) |new_vma| {
                        errdefer krn.mm.kfree(new_vma);
                        new_vma.mm = _mmap;
                        vma.dup(new_vma, vas_pair) catch {
                            _mmap.delete();
                            mm.virt_memory_manager.pmm.freePage(vas_pair.phys);
                            krn.mm.kfree(_mmap);
                            return null;
                        };
                        if (_mmap.vmas) |c| c.list.addTail(&new_vma.list) else _mmap.vmas = new_vma;
                    }
                }
            }
            _mmap.stack_top = self.stack_top;
            _mmap.stack_bottom = self.stack_bottom;
            _mmap.bss = self.bss;
            _mmap.code = self.code;
            _mmap.data = self.data;
            _mmap.heap = self.heap;
            _mmap.brk_start = self.brk_start;
            _mmap.brk = self.brk;
            _mmap.argc = self.argc;
            _mmap.arg_start = self.arg_start;
            _mmap.arg_end = self.arg_end;
            _mmap.env_start = self.env_start;
            _mmap.env_end = self.env_end;
        }
        return mmap;
    }

    pub fn delete(self: *MM) void {
        self.releaseMappings();
        if (self != &init_mm and self.vas != 0) {
            mm.virt_memory_manager.deleteVAS(self.vas);
        }
        krn.mm.kfree(self);
    }

    pub fn releaseMappings(self: *MM) void {
        if (self == &init_mm)
            return ;

        if (self.vmas) |head| {
            while (!head.list.isEmpty()) {
                const vma: *VMA = head.list.next.?.entry(VMA, "list");
                vma.list.del();

                mm.virt_memory_manager.releaseArea(vma.start, vma.end, vma.flags.TYPE);
                krn.mm.kfree(vma);
            }
            mm.virt_memory_manager.releaseArea(head.start, head.end, head.flags.TYPE);
            krn.mm.kfree(head);
        }
        self.vmas = null;
    }

    pub inline fn isCurrentMM(self: *MM) bool {
        return krn.task.current.mm.? == self;
    }

    pub fn accessTaskVM(self: *MM, addr: usize, len: usize) ![]u8 {
        if (krn.mm.kmallocSlice(u8, len)) |res| {
            const curr_vas = krn.task.current.mm.?.vas;
            if (!self.isCurrentMM())
                arch.vmm.switchToVAS(self.vas);
            const src: [*]u8 = @ptrFromInt(addr);
            @memcpy(res[0..len], src[0..len]);
            if (!self.isCurrentMM())
                arch.vmm.switchToVAS(curr_vas);
            return res;
        }
        return krn.errors.PosixError.ENOMEM;
    }
};

pub var init_mm: MM = MM.init();
