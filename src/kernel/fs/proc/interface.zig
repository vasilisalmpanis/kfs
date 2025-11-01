const inode = @import("inode.zig");
const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");

pub fn mkdir(parent: *fs.DEntry, name: []const u8) !*fs.DEntry {
    const mode = kernel.fs.UMode{
        .usr = 5,
        .grp = 5,
        .other = 5,
        .type = fs.S_IFDIR,
    };
    return try parent.inode.ops.mkdir(parent.inode, parent, name, mode);
}

pub fn createFile(parent: *fs.DEntry, name: []const u8, fops: *const fs.FileOps, mode: fs.UMode) !*fs.DEntry {
    _ = parent.inode.ops.lookup(parent, name) catch {
        const new_file = try parent.inode.ops.create(parent.inode, name, mode, parent);
        new_file.inode.fops = fops;
        return new_file;
    };
    return kernel.errors.PosixError.EEXIST;
}
