const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const arch = @import("arch");

pub fn brk(addr: u32) !u32 {
    const current_brk = krn.task.current.mm.?.brk;

    var req = addr;
    // If addr is 0, return current break (heap end)
    if (req == 0) {
        krn.logger.INFO("brk(0) returning current heap: 0x{x}\n", .{current_brk});
        return current_brk;
    }
    if (req < krn.task.current.mm.?.brk_start) {
        req = krn.task.current.mm.?.brk_start;
    }
    if (req < current_brk) {
        _ = try krn.do_munmap(krn.task.current.mm.?, req, current_brk);
        krn.task.current.mm.?.brk = req;
        return 0;
    }
    if (req == current_brk)
        return 0;
    const len = arch.pageAlign(req - current_brk, false);
    const new_brk = try krn.task.current.mm.?.mmap_area(current_brk,
        len,
        krn.mm.PROT_RW, 
        krn.mm.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
        },
        null,
        0
    );
    // TODO: fix brk cuz its broken
    krn.task.current.mm.?.brk = new_brk;
    return 0;
}
