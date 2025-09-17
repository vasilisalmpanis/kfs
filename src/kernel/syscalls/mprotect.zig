const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

pub fn mprotect(addr: u32, len: u32, prot: u32) !u32 {
    kernel.logger.DEBUG("mprotect addr {x}, len {d}, prot {x}", .{addr, len, prot});
    if (len == 0)
        return 0;
    return 0;
}
