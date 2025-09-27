const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const krn = @import("../main.zig");
const mm = @import("../mm/proc_mm.zig");

pub fn mprotect(
    addr: ?*anyopaque,
    len: u32,
    prot: u32
) !u32 {
    krn.logger.DEBUG(
        "mprotect addr {x}, len {d}, prot {x}",
        .{@intFromPtr(addr), len, prot}
    );
    return 0;
}
