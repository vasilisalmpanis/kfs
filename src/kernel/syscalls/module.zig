const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");
const mod = @import("modules");

pub fn init_module(image: [*]u8, size: u32, name: [*]u8, name_len: u32) !u32 {
    const name_span = name[0..name_len];
    _ = try mod.load_module(image[0..size], name_span);
    return 0;
}

