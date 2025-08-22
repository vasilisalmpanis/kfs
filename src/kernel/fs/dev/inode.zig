const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const drv = @import("drivers");


pub const DevInode = struct {
    base: fs.Inode,
    buff: [50]u8,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(DevInode)) |inode| {
            inode.base.setup(sb);
            inode.base.ops = &dev_inode_ops;
            inode.base.size = 50;
            inode.buff = .{0} ** 50;
            return &inode.base;
        }
        return error.OutOfMemory;
    }

    fn lookup(dir: *fs.Inode, name: []const u8) !*fs.DEntry {
        const key: fs.DentryHash = fs.DentryHash{
            .ino = dir.i_no,
            .name = name,
        };
        if (fs.dcache.get(key)) |entry| {
            return entry;
        }
        return error.InodeNotFound;
    }

    fn mkdir(base: *fs.Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        if (kernel.mm.dupSlice(u8, name)) |_name| {
            const cash_key = fs.DentryHash{
                .ino = base.i_no,
                .name = _name,
            };
            if (fs.dcache.get(cash_key)) |_| {
                return error.Exists;
            }
            var new_inode = try DevInode.new(base.sb);
            new_inode.mode = mode;
            new_inode.mode.type |= kernel.fs.S_IFDIR;
            errdefer kernel.mm.kfree(new_inode);
            var new_dentry = try fs.DEntry.alloc(_name, base.sb, new_inode);
            errdefer kernel.mm.kfree(new_dentry);
            parent.tree.addChild(&new_dentry.tree);
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
        if (base.mode.type != fs.S_IFDIR)
            return error.NotDirectory;
        if (!base.mode.isWriteable())
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(base, name) catch {
            const new_inode = try DevInode.new(base.sb);
            errdefer kernel.mm.kfree(new_inode);
            new_inode.mode = mode;
            var dent = try parent.new(name, new_inode);
            dent.ref.ref();
            return dent;
        };
        return error.Exists;
    }
};

var dev_inode_ops = fs.InodeOps {
    // .file_ops = &file.DevFileOps,
    .create = DevInode.create,
    .mknod = DevInode.mknod,
    .lookup = DevInode.lookup,
    .mkdir = DevInode.mkdir,
};
