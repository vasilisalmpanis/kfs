const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

pub fn symlink(target: ?[*:0]u8, linkpath: ?[*:0]u8) !u32 {
    _ = target;
    _ = linkpath;
    // TODO
    return 0;
}
