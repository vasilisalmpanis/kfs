const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

pub fn fcntl(fd: u32, op: i32, arg: u32) !u32 {
    kernel.logger.DEBUG("fcntl fd: {d}, op: {d}, arg: {d}", .{fd, op, arg});
    return 0;
}
