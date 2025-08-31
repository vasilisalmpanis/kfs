const std = @import("std");
const krn = @import("../main.zig");
const fs = @import("./fs.zig");

const PathError = error{
    WrongPath,
};

pub const Path = struct {
    mnt: *fs.Mount,
    dentry: *fs.DEntry,

    pub fn init(mnt: *fs.Mount, dentry: *fs.DEntry) Path {
        dentry.ref.ref();
        return Path{
            .mnt = mnt,
            .dentry = dentry,
        };
    }

    pub fn clone(self: *const Path) Path {
        return Path.init(self.mnt, self.dentry);
    }

    pub fn release(self: *const Path) void {
        self.dentry.ref.unref();
    }

    pub fn isRoot(self: *Path) bool {
        return self.dentry.sb.root == self.dentry;
    }

    pub fn resolveMount(self: *Path) void {
        if (self.mnt.checkChildMount(self.dentry)) |child_mnt| {
            self.mnt = child_mnt;
            self.setDentry(child_mnt.sb.root);
        }
    }

    pub fn setDentry(self: *Path, dent: *fs.DEntry) void {
        dent.ref.ref();
        self.dentry.ref.unref();
        self.dentry = dent;
    }

    pub fn stepInto(self: *Path, segment: [] const u8) !void {
        if (std.mem.eql(u8, segment, "..")) {
            if (self.isRoot()) {
                if (self.mnt.root.tree.parent) |d| {
                    if (self.mnt.tree.parent) |p| {
                        self.mnt = p.entry(fs.Mount, "tree");
                        self.setDentry(d.entry(fs.DEntry, "tree"));
                    } else {
                        return error.WrongPath;
                    }
                } else {
                    return error.WrongPath;
                }
            } else {
                if (self.dentry.tree.parent) |p| {
                    self.setDentry(p.entry(fs.DEntry, "tree"));
                } else {
                    return error.WrongPath;
                }
            }
        } else if (!std.mem.eql(u8, segment, ".")) {
            const dentry = self.dentry.inode.ops.lookup(
                self.dentry,
                segment
            ) catch |err| {
                return err;
            };
            self.setDentry(dentry);
        }
        self.resolveMount();
    }
};

pub fn remove_trailing_slashes(path: []const u8) []const u8 {
    var len = path.len - 1;
    if (path.len == 1 and path[0] == '/')
        return path;
    while(len > 0 and path[len] == '/') : (len = len - 1) {
    }
    if (len != path.len)
        len = len + 1;
    return path[0..len];
}

pub fn dir_resolve(path: []const u8, last: *[]const u8) !Path {
    if (path.len == 0) {
        return PathError.WrongPath;
    }

    var cwd = krn.task.initial_task.fs.pwd;
    if (path[0] == '/') {
        cwd = krn.task.initial_task.fs.root;
    }
    var curr = Path.init(
        cwd.mnt,
        cwd.dentry
    );
    try curr.stepInto(".");
    var it = std.mem.tokenizeScalar(
        u8,
        path,
        '/'
    );
    while (it.next()) |segment| {
        if (it.rest().len == 0) {
            last.* = segment;
            return curr;
        }
        try curr.stepInto(segment);
    }
    return curr;
}

pub fn resolve(path: []const u8) !Path {
    var last: [] const u8 = "";
    var res = try dir_resolve(path, &last);
    if (last.len > 0) {
        try res.stepInto(last);
    }
    return res;
}
