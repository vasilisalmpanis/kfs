const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const arch = @import("arch");

pub fn brk(addr: u32) !u32 {
    const mm = krn.task.current.mm
        orelse return 0;
    const current_brk = mm.brk;

    // If addr is 0, return current break (heap end)
    if (addr == 0) {
        krn.logger.INFO("brk(0) returning current heap: 0x{x}\n", .{current_brk});
        return current_brk;
    }

    var req = addr;
    if (req < mm.brk_start) {
        req = mm.brk_start;
    }

    // Shrinking the brk
    if (req < current_brk) {
        const aligned_req = arch.pageAlign(req, false);
        const aligned_current = arch.pageAlign(current_brk, false);
        if (aligned_req < aligned_current) {
            _ = krn.do_munmap(mm, aligned_req, aligned_current) catch {
                return current_brk;
            };
        }
        mm.brk = req;
        krn.logger.INFO("brk shrinking to 0x{x}\n", .{req});
        return req;
    }

    if (req == current_brk)
        return current_brk;

    // Expanding the brk
    const aligned_current = arch.pageAlign(current_brk, false);
    const aligned_req = arch.pageAlign(req, false);
    
    if (aligned_req > aligned_current) {
        const len = aligned_req - aligned_current;
        _ = mm.mmap_area(
            aligned_current,
            len,
            krn.mm.PROT_RW,
            krn.mm.MAP{
                .TYPE = .PRIVATE,
                .ANONYMOUS = true,
                .FIXED = true,
            },
            null,
            0
        ) catch {
            krn.logger.WARN(
                "brk expansion failed, returning current: 0x{x}\n",
                .{current_brk}
            );
            return current_brk;
        };
    }
    
    mm.brk = req;
    return req;
}
