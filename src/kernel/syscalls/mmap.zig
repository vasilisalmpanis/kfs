const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const krn = @import("../main.zig");
const mm = @import("../mm/proc_mm.zig");

const mmap_struct = extern struct {
	addr: u32,
	len: u32,
	prot: u32,
	flags: u32,
	fd: u32,
	offset: u32,
};

pub fn mmap(
    arg: ?*mmap_struct
) !u32 {
    krn.logger.INFO("length {x}\n", .{arg.?.len});
    return try mmap2(@ptrFromInt(arg.?.addr), arg.?.len, arg.?.prot, @bitCast(arg.?.flags), -1, 0);
}

pub fn mmap2(
    addr: ?*anyopaque,
    length: u32,
    prot: u32,
    flags: mm.MAP,
    fd: i32,
    off: u32,
) !u32 {
    krn.logger.DEBUG(\\mmap2
        \\  addr:  0x{x:0>8}
        \\  size:  {d:<10}
        \\  prot:  0x{x:0>8}
        \\  fd:    {d:<10}
        \\  off:   {d:<10}
        \\  flags: type:      {t}
        \\         anon:      {}
        \\         fixed:     {}
        \\         stack:     {}
        \\         growsdown: {}
        \\         exec:      {}
        \\
        ,.{
            @intFromPtr(addr),
            length, prot, fd, off,
            flags.TYPE, flags.ANONYMOUS, flags.FIXED,
            flags.STACK, flags.GROWSDOWN, flags.EXECUTABLE
    });
    if (prot & ~(mm.PROT_EXEC | mm.PROT_READ | mm.PROT_WRITE | mm.PROT_NONE) > 0)
        return errors.EINVAL;
    // addr specifies the wanted virtual address (suggestion)
    // length is the size of the mapping
    const len: u32 = arch.pageAlign(length, false);
    var hint: u32 = @intFromPtr(addr);
    if (addr != null) {
        if (hint & (arch.PAGE_SIZE - 1) > 0) {
            if (flags.FIXED) {
                return errors.EINVAL;
            }
            hint = arch.pmm.pageAlign(hint, false);
        }
        if (hint < krn.task.current.mm.?.heap)
            hint = krn.task.current.mm.?.heap;
    } else {
        // look through mappings and just give back one.
        hint = krn.task.current.mm.?.heap;
    }
    // TODO: not adding READ and WRITE flags but implement mprotect
    return try krn.task.current.mm.?.mmap_area(hint, len, prot | mm.PROT_WRITE | mm.PROT_READ, flags);
}

pub fn do_munmap(task_mm: *krn.mm.MM, start: u32, end: u32) !u32 {
    if (task_mm.vmas) |head| {
        var current_node: ?*krn.list.ListHead = &head.list;

        while (current_node) |node| {
            const vma = node.entry(krn.mm.VMA, "list");
            if (vma.start > end)
                break;
            const next_node = if (node.next == &head.list) null else node.next;

            // Check if this VMA overlaps with the unmap range
            if (vma.end <= start or vma.start >= end) {
                current_node = next_node;
                continue;
            }

            if (vma.start >= start and vma.end <= end) {
                // 1. Remove the whole mapping.
                if (node == &head.list) {
                    if (next_node) |next| {
                        task_mm.vmas = next.entry(krn.mm.VMA, "list");
                    } else {
                        task_mm.vmas = null;
                    }
                }

                node.del();
                krn.mm.virt_memory_manager.releaseArea(vma.start, vma.end, vma.flags.TYPE);
                krn.mm.kfree(vma);
            } else if (vma.start < start and vma.end > end) {
                // 2. Split mapping into 2 parts.
                const new_vma = mm.VMA.allocEmpty();
                if (new_vma == null) return errors.ENOMEM;
                new_vma.?.start = end;
                new_vma.?.end = vma.end;
                new_vma.?.mm = task_mm;
                new_vma.?.prot = vma.prot;
                new_vma.?.flags = vma.flags;
                new_vma.?.mm = task_mm;
                vma.end = start;
                node.add(&new_vma.?.list);

                krn.mm.virt_memory_manager.releaseArea(start, end, vma.flags.TYPE);
            } else if (vma.start < start and vma.end > start) {
                // 3. Partially remove mapping from the end.
                krn.mm.virt_memory_manager.releaseArea(start, vma.end, vma.flags.TYPE);
                vma.end = start;

            } else if (vma.start < end and vma.end > end) {
                // 4. Partially remove mapping from the beginning.
                krn.mm.virt_memory_manager.releaseArea(vma.start, end, vma.flags.TYPE);
                vma.start = end;
            }

            current_node = next_node;
        }
    }
    return 0;
}

// munmap() removes any mappings in the specified address range, and causes further references to
// addresses within the range to generate invalid memory references.
// It is not an error if the indicated range does not contain any mapped pages.
//
// On success, munmap() returns 0, on failure -1, and errno is set (probably to
pub fn munmap(
    addr: ?*anyopaque,
    length: u32,
) !u32 {
    const len: u32 = arch.pageAlign(length, false);
    const start: u32 = @intFromPtr(addr);
    if (start & (arch.PAGE_SIZE - 1) > 0)
        return errors.EINVAL;
    if (start + len > krn.mm.PAGE_OFFSET)
        return errors.EINVAL;
    if (krn.task.current.mm == null)
        return errors.EINVAL;
    return try do_munmap(krn.task.current.mm.?, start, start + len);
}
