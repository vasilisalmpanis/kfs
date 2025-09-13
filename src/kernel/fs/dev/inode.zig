const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const drv = @import("drivers");


pub const DevInode = struct {
    base: fs.Inode,
    buff: [50]u8,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(DevInode)) |inode| {
            inode.base.dev_id = drv.device.dev_t{
                .major = 0,
                .minor = 0,
            };
            inode.base.setup(sb);
            inode.base.ops = &dev_inode_ops;
            inode.base.fops = &file.DevFileOps;
            inode.base.size = 50;
            inode.buff = .{0} ** 50;
            return &inode.base;
        }
        return error.OutOfMemory;
    }

    fn lookup(dir: *fs.DEntry, name: []const u8) !*fs.DEntry {
        if (!dir.inode.mode.isDir()) {
            return kernel.errors.PosixError.ENOTDIR;
        }
        if (!dir.inode.mode.canExecute(
            dir.inode.uid,
            dir.inode.gid
        )) {
            return kernel.errors.PosixError.EACCES;
        }
        const key: fs.DentryHash = fs.DentryHash{
            .sb = @intFromPtr(dir.sb),
            .ino = dir.inode.i_no,
            .name = name,
        };
        if (fs.dcache.get(key)) |entry| {
            return entry;
        }
        return error.InodeNotFound;
    }

    fn mkdir(base: *fs.Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        if (kernel.mm.dupSlice(u8, name)) |_name| {
            var cash_key = fs.DentryHash{
                .sb = @intFromPtr(parent.sb),
                .ino = base.i_no,
                .name = _name,
            };
            if (fs.dcache.get(cash_key)) |_| {
                return error.Exists;
            }
            var new_inode = try DevInode.new(base.sb);
            new_inode.setCreds(
                kernel.task.current.uid,
                kernel.task.current.gid,
                mode
            );
            new_inode.mode.type |= kernel.fs.S_IFDIR;
            errdefer kernel.mm.kfree(new_inode);
            var new_dentry = try fs.DEntry.alloc(_name, base.sb, new_inode);
            errdefer kernel.mm.kfree(new_dentry);
            parent.tree.addChild(&new_dentry.tree);
            cash_key.name = new_dentry.name;
            try fs.dcache.put(cash_key, new_dentry);
            return new_dentry;
        } else {
            return error.OutOfMemory;
        }
    }

    fn mknod(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry, dev: drv.device.dev_t) anyerror!*fs.DEntry {
        const special: *fs.DEntry = base.ops.create(base, name, mode, parent) catch {
            return kernel.errors.PosixError.ENOENT;
        };
        special.inode.dev_id = dev;
        switch (mode.type) {
            fs.S_IFCHR => {
                special.inode.fops = &drv.cdev.cdev_default_ops;
            },
            fs.S_IFBLK => {
                special.inode.fops = &drv.bdev.bdev_default_ops;
            },
            else => {
                @panic("TODO");
            },
        }
        return special;
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        if (!base.mode.isDir())
            return error.NotDirectory;
        if (!base.mode.canWrite(base.uid, base.gid))
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            const new_inode = try DevInode.new(base.sb);
            // new_inode.dev_id = 0;
            errdefer kernel.mm.kfree(new_inode);
            new_inode.setCreds(
                kernel.task.current.uid,
                kernel.task.current.gid,
                mode
            );
            var dent = try parent.new(name, new_inode);
            dent.ref.ref();
            return dent;
        };
        return error.Exists;
    }
};

var dev_inode_ops = fs.InodeOps {
    .create = DevInode.create,
    .mknod = DevInode.mknod,
    .lookup = DevInode.lookup,
    .mkdir = DevInode.mkdir,
    .get_link = null,
};
