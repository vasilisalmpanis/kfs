const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const arch = @import("arch");

pub fn brk(addr: u32) !u32 {
    const current_heap = krn.task.current.mm.?.heap;

    // If addr is 0, return current break (heap end)
    if (addr == 0) {
        krn.logger.INFO("brk(0) returning current heap: 0x{x}\n", .{current_heap});
        return current_heap;
    }
    if (addr < current_heap)
        return errors.EINVAL;
    const len = arch.pageAlign(addr - current_heap, false);
    const new_heap = try krn.task.current.mm.?.mmap_area(current_heap,
        len,
        krn.mm.PROT_RW, 
        krn.mm.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
        },
    );
    // TODO: fix brk cuz its broken
    krn.task.current.mm.?.heap = new_heap + len;
    return 0;
}
