const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const arch = @import("arch");

pub fn brk(addr: u32, _: u32, _: u32, _: u32, _: u32, _: u32) !u32 {
    _ = addr;
    return errors.ENOMEM;
    // const current_heap = krn.mm.proc_mm.init_mm.heap;
    //
    // // If addr is 0, return current break (heap end)
    // if (addr == 0) {
    //     krn.logger.INFO("brk(0) returning current heap: 0x{x}\n", .{current_heap});
    //     return current_heap;
    // }
    //
    // // TODO: Implement proper heap expansion/contraction
    // // For now, just return the current heap to avoid null pointer issues
    // krn.logger.INFO("brk(0x{x}) requested, returning current heap: 0x{x}\n", .{addr, current_heap});
    // return current_heap;
}
