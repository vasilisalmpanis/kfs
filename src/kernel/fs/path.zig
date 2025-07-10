const std = @import("std");
const krn = @import("../main.zig");
const fs = @import("./fs.zig");

const PathError = error{
    WrongPath,
};

pub fn remove_trailing_slashes(path: []const u8) []const u8 {
    var len = path.len - 1;
    while(len > 0 and path[len] == '/') : (len = len - 1) {
    }
    if (len != path.len)
        len = len + 1;
    return path[0..len];
}

pub fn dir_resolve(path: []const u8, last: *[]const u8) !*fs.DEntry {
    if (path.len == 0) {
        return PathError.WrongPath;
    }

    var cwd = krn.task.initial_task.fs.pwd;
    if (path[0] == '/') {
        cwd = krn.task.initial_task.fs.root;
    }

    var d_curr = cwd.dentry;
    var it = std.mem.tokenizeScalar(
        u8,
        path,
        '/'
    );
    while (it.next()) |segment| {
        if (it.rest().len == 0) {
            last.* = segment;
            return d_curr;
        }
        const d_tmp = d_curr.inode.ops.lookup(
            d_curr.inode,
            segment
        ) catch |err| {
            return err;
        };
        d_curr = d_tmp;
    }
    return d_curr;
}
