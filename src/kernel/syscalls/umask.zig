const std = @import("std");
const krn = @import("../main.zig");
const fs = @import("../fs/fs.zig");
const errors = @import("error-codes.zig").PosixError;

pub fn umask(mask: u32) !u32 {
    const ret = krn.task.current.fs.umask;
    krn.task.current.fs.umask = (mask & 0o777);
    return ret;
}
