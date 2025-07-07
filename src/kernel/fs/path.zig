const std = @import("std");
const krn = @import("kernel");
const fs = @import("./fs.zig");

const PathError = error{
    WrongPath,
};

pub fn resolve(path: []const u8) !*fs.DEntry {
    if (path.len == 0) {
        return PathError.WrongPath;
    }

    var cwd = krn.task.current.fs.?.pwd;
    if (path[0] == '/') {
        cwd = krn.task.current.fs.?.root;
    }

    var d_curr = cwd.dentry;
    var it = std.mem.tokenizeScalar(
        u8,
        path,
        '/'
    );
    while (it.next()) |segment| {
        const d_tmp = d_curr.inode.ops.lookup(segment) catch |err| {
            switch (err) {}
        };
        d_curr = d_tmp;
    }
    return d_curr;
}
