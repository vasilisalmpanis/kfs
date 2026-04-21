const arch = @import("arch");
const krn = @import("./main.zig");

pub const VdsoData = extern struct {
    seq: u32 = 0,
    monotonic_sec: i32 = 0,
    monotonic_nsec: i32 = 0,
    realtime_sec: i64 = 0,
    realtime_nsec: i32 = 0,
    _pad: i32 = 0,
};

const vdso_image = @import("vdso_image").data;

pub var vvar_phys: usize = 0;
var vvar_data: *volatile VdsoData = undefined;

var code_phys: [max_code_pages]usize = [_]usize{0} ** max_code_pages;
var code_page_count: usize = 0;
const max_code_pages = 4; // This can be increase if needed

pub fn init() void {
    const num_code_pages = imagePages();
    if (num_code_pages > max_code_pages)
        @panic("vdso: image too large");

    const lock_state = krn.mm.mem_lock.lock_irq_disable();
    const vvar_page = krn.mm.virt_memory_manager.pmm.allocPage();
    if (vvar_page == 0)
        @panic("vdso: cannot allocate vvar page");

    const vvar_virt = krn.mm.virt_memory_manager.findFreeSpace(
        1, krn.mm.PAGE_OFFSET, 0xFFFFF000, false,
    );
    if (vvar_virt == 0xFFFFFFFF)
        @panic("vdso: cannot find kernel virtual space for vvar");

    krn.mm.virt_memory_manager.mapPage(vvar_virt, vvar_page, .{
        .present = true,
        .writable = true,
        .user = false,
    });

    const code_virt = krn.mm.virt_memory_manager.findFreeSpace(
        @intCast(num_code_pages), krn.mm.PAGE_OFFSET, 0xFFFFF000, false,
    );
    if (code_virt == 0xFFFFFFFF)
        @panic("vdso: cannot find kernel virtual space for code");

    for (0..num_code_pages) |i| {
        const phys = krn.mm.virt_memory_manager.pmm.allocPage();
        if (phys == 0)
            @panic("vdso: cannot allocate code page");
        code_phys[i] = phys;
        krn.mm.virt_memory_manager.mapPage(
            @intCast(code_virt + i * arch.PAGE_SIZE),
            phys,
            .{ .present = true, .writable = true, .user = false },
        );
    }

    krn.mm.mem_lock.unlock_irq_enable(lock_state);

    code_page_count = num_code_pages;
    vvar_phys = vvar_page;
    vvar_data = @ptrFromInt(vvar_virt);

    // Initialize the variables to 0
    const zero_ptr: [*]u8 = @ptrFromInt(vvar_virt);
    @memset(zero_ptr[0..arch.PAGE_SIZE], 0);

    const dest: [*]u8 = @ptrFromInt(code_virt);
    @memcpy(dest[0..vdso_image.len], vdso_image);

    // Set padding to 0. We could maybe in the future do that
    // at compile time but for now its not worth the effort.
    if (vdso_image.len < num_code_pages * arch.PAGE_SIZE) {
        @memset(dest[vdso_image.len .. num_code_pages * arch.PAGE_SIZE], 0);
    }

    krn.logger.INFO("vDSO: vvar phys=0x{X:0>8} kern_virt=0x{X:0>8} image_size={d} code_pages={d}", .{
        vvar_page, vvar_virt, vdso_image.len, num_code_pages,
    });
    if (krn.cmos_ready.*) {
        const monotonic = krn.getTimeFromStart();
        const realtime_sec: u64 = krn.cmos.toUnixSeconds(krn.cmos);
        vvar_data.realtime_sec = @intCast(realtime_sec);
        vvar_data.realtime_nsec = monotonic.tv_nsec;
    }
}

pub inline fn updateTime(sec: i32, nsec: i32) void {
    if (vvar_phys == 0) return;

    vvar_data.seq +%= 1;
    asm volatile ("" ::: .{ .memory = true });
    vvar_data.monotonic_sec += sec;
    vvar_data.monotonic_nsec =
        if (nsec == 0) 0
        else vvar_data.monotonic_nsec + nsec;
    vvar_data.realtime_sec += sec;
    vvar_data.realtime_nsec = vvar_data.monotonic_nsec;
    asm volatile ("" ::: .{ .memory = true });
    vvar_data.seq +%= 1;
}

pub fn imageSize() usize {
    return vdso_image.len;
}

pub fn imagePages() usize {
    const size = vdso_image.len;
    return (size + arch.PAGE_SIZE - 1) / arch.PAGE_SIZE;
}

pub fn mapIntoUserspace(mm: *krn.mm.MM, vdso_base: usize) !void {
    const vvar_addr = vdso_base;
    const vdso_code_addr = vdso_base + arch.PAGE_SIZE;

    // Map the shared vvar page (read-only for userspace)
    const vvar_vma = krn.mm.VMA.allocEmpty() orelse return error.OutOfMemory;
    vvar_vma.start = vvar_addr;
    vvar_vma.end = vvar_addr + arch.PAGE_SIZE;
    vvar_vma.mm = mm;
    vvar_vma.flags = krn.mm.MAP{ .TYPE = .SHARED, .ANONYMOUS = true };
    vvar_vma.prot = krn.mm.PROT_READ;
    vvar_vma.file = null;
    vvar_vma.offset = 0;

    {
        const lock_state = krn.mm.mem_lock.lock_irq_disable();
        krn.mm.virt_memory_manager.mapPage(@intCast(vvar_addr), @intCast(vvar_phys), .{
            .present = true,
            .writable = false,
            .user = true,
        });
        krn.mm.mem_lock.unlock_irq_enable(lock_state);
    }

    if (mm.vmas) |head| {
        head.list.addTail(&vvar_vma.list);
    } else {
        vvar_vma.list.setup();
        mm.vmas = vvar_vma;
    }

    // Map the shared vDSO code pages (read-only for userspace)
    const code_vma = krn.mm.VMA.allocEmpty() orelse return error.OutOfMemory;
    code_vma.start = vdso_code_addr;
    code_vma.end = vdso_code_addr + code_page_count * arch.PAGE_SIZE;
    code_vma.mm = mm;
    code_vma.flags = krn.mm.MAP{ .TYPE = .SHARED, .ANONYMOUS = true };
    code_vma.prot = krn.mm.PROT_READ;
    code_vma.file = null;
    code_vma.offset = 0;

    {
        const lock_state = krn.mm.mem_lock.lock_irq_disable();
        for (0..code_page_count) |i| {
            krn.mm.virt_memory_manager.mapPage(
                @intCast(vdso_code_addr + i * arch.PAGE_SIZE),
                @intCast(code_phys[i]),
                .{ .present = true, .writable = false, .user = true },
            );
        }
        krn.mm.mem_lock.unlock_irq_enable(lock_state);
    }

    if (mm.vmas) |head| {
        head.list.addTail(&code_vma.list);
    } else {
        code_vma.list.setup();
        mm.vmas = code_vma;
    }
}
