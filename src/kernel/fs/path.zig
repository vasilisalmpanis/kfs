const std = @import("std");
const krn = @import("../main.zig");
const fs = @import("./fs.zig");

pub const Path = struct {
    mnt: *fs.Mount,
    dentry: *fs.DEntry,

    pub fn init(mnt: *fs.Mount, dentry: *fs.DEntry) Path {
        dentry.ref.ref();
        mnt.count.ref();
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
        self.mnt.count.unref();
    }

    pub fn isRoot(self: *const Path) bool {
        return self.dentry.sb.root == self.dentry;
    }

    pub fn resolveMount(self: *Path) void {
        if (self.mnt.checkChildMount(self.dentry)) |child_mnt| {
            child_mnt.count.ref();
            self.mnt.count.unref();
            self.mnt = child_mnt;
            self.setDentry(child_mnt.sb.root);
        }
    }

    pub fn setDentry(self: *Path, dent: *fs.DEntry) void {
        dent.ref.ref();
        self.dentry.ref.unref();
        self.dentry = dent;
    }

    pub fn followLink(self: *Path, prev_path: Path) anyerror!void {
        if (self.dentry.inode.ops.get_link) |getLink| {
            var path: [1024]u8 = .{0} ** 1024;
            var path_slice: []u8 = path[0..1024];
            try getLink(self.dentry.inode, &path_slice);
            const new_path = try resolveFrom(path_slice, prev_path, true);
            self.release();
            self.dentry = new_path.dentry;
            self.mnt = new_path.mnt;
        } else {
            return krn.errors.PosixError.EINVAL;
        }
    }

    pub fn stepInto(self: *Path, segment: [] const u8, follow: bool) !void {
        if (segment.len == 0) return;
        var prev_path: Path = self.clone();
        defer prev_path.release();
        if (std.mem.eql(u8, segment, "..")) {
            if (self.isRoot()) {
                if (self.mnt == krn.task.current.fs.root.mnt) {
                    return;
                }
                if (self.mnt.root.tree.parent) |d| {
                    if (self.mnt.tree.parent) |p| {
                        self.mnt.count.unref();
                        self.mnt = p.entry(fs.Mount, "tree");
                        self.setDentry(d.entry(fs.DEntry, "tree"));
                    } else {
                        return krn.errors.PosixError.EINVAL;
                    }
                } else {
                    return krn.errors.PosixError.EINVAL;
                }
            } else {
                if (self.dentry.tree.parent) |p| {
                    self.setDentry(p.entry(fs.DEntry, "tree"));
                } else {
                    return krn.errors.PosixError.EINVAL;
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
        if (self.dentry.inode.mode.isLink() and follow) {
            try self.followLink(prev_path);
        }
    }

    pub fn getAbsPath(self: Path, buf: []u8) ![]u8 {
        if (
            self.isRoot() and self.mnt.isGlobalRoot() 
        ) {
            return buf[0..0];
        }
        var curr = try resolveFrom("..", self, true);
        const res = try curr.getAbsPath(buf);
        buf[res.len] = '/';
        var _d: *fs.DEntry = undefined;
        if (self.isRoot()) {
            _d = self.mnt.root;
        } else {
            _d = self.dentry;
        }
        if (res.len + _d.name.len + 1  > buf.len) {
            return krn.errors.PosixError.ENOMEM;
        }
        @memcpy(
            buf[res.len + 1..res.len + _d.name.len + 1],
            _d.name
        );
        return buf[0..res.len + _d.name.len + 1];
    }

    pub fn isSubPathOf(self: *const Path, other: *const Path) bool {
        var tree_node: ?*krn.tree.TreeNode = &self.dentry.tree;
        while (tree_node) |node| {
            if (node == &other.dentry.tree)
                return true;
            tree_node = node.parent;
        }
        return false;
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
        return krn.errors.PosixError.EINVAL;
    }

    var cwd = krn.task.current.fs.pwd;
    if (path[0] == '/') {
        cwd = krn.task.current.fs.root;
    }
    var curr = Path.init(
        cwd.mnt,
        cwd.dentry
    );
    try curr.stepInto(".", true);
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
        try curr.stepInto(segment, true);
    }
    return curr;
}

pub fn dir_resolve_from(path: []const u8, from: Path, last: *[]const u8) !Path {
    if (path.len == 0) {
        return krn.errors.PosixError.EINVAL;
    }

    var cwd = from;
    if (path[0] == '/') {
        cwd = krn.task.current.fs.root;
    }
    var curr = Path.init(
        cwd.mnt,
        cwd.dentry
    );
    try curr.stepInto(".", true);
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
        try curr.stepInto(segment, true);
    }
    return curr;
}

pub fn isRelative(path: []const u8) bool {
    if (path.len != 0 and path[0] != '/')
        return true;
    return false;
}

pub fn resolveFrom(path: []const u8, from: Path, follow: bool) !Path {
    var last: [] const u8 = "";
    var res = try dir_resolve_from(path, from, &last);
    if (last.len > 0) {
        try res.stepInto(last, follow);
    }
    return res;
}

pub fn resolve(path: []const u8) !Path {
    var last: [] const u8 = "";
    var res = try dir_resolve(path, &last);
    if (last.len > 0) {
        try res.stepInto(last, true);
    }
    return res;
}
