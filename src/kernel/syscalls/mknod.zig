const errors = @import("./error-codes.zig").PosixError;
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");
const drv = @import("drivers");

pub fn mknod(
    pathname: [*:0]const u8,
    mode: fs.UMode,
    dev: u32,
) !u32 {
    var name: []const u8 = undefined;
    const path = std.mem.span(pathname);
    const parent_dir = try fs.path.dir_resolve(path, &name);
    if (!parent_dir.dentry.inode.mode.isDir()) {
        return errors.ENOENT;
    }
    var can_create_name: bool = false;
    _ = parent_dir.dentry.inode.ops.lookup(
        parent_dir.dentry.inode,
        name
    ) catch |err| {
        switch (err) {
            error.InodeNotFound => {
                can_create_name = true;
            },
            else => return err
        }
    };
    if (!can_create_name) {
        return errors.EEXIST;
    }

    switch (mode.type) {
        fs.S_IFBLK, fs.S_IFCHR => return do_mknod(
            parent_dir,
            name,
            mode,
            drv.device.dev_t.from_u32(dev)
        ),
        fs.S_IFREG => {},
        fs.S_IFIFO => {},
        fs.S_IFSOCK => {},
        fs.S_IFDIR => return errors.EPERM,
        else => return errors.EINVAL
    }
    return errors.ENOENT;
}

fn do_mknod(parent: fs.path.Path, name: []const u8, mode: fs.UMode, dev: drv.device.dev_t) !u32 {
    if (parent.dentry.inode.ops.mknod) |_mknod| {
        _ = _mknod(
            parent.dentry.inode,
            name,
            mode,
            parent.dentry,
            dev
        ) catch |err| {
            switch (err) {
                error.OutOfMemory => { return errors.ENOMEM; },
                error.Access => { return errors.EACCES; },
                else => { return errors.ENOENT; },
            }
        };
    } else {
        return errors.EPERM;
    }
    return 0;
}
