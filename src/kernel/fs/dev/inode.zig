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
        const sb: *fs.SuperBlock = if (base.sb != null) base.sb.? else return kernel.errors.PosixError.EINVAL;
        if (kernel.mm.dupSlice(u8, name)) |_name| {
            var cash_key = fs.DentryHash{
                .sb = @intFromPtr(parent.sb),
                .ino = base.i_no,
                .name = _name,
            };
            if (fs.dcache.get(cash_key)) |_| {
                return error.Exists;
            }
            var new_inode = try DevInode.new(sb);
            new_inode.setCreds(
                kernel.task.current.uid,
                kernel.task.current.gid,
                mode
            );
            new_inode.mode.type |= kernel.fs.S_IFDIR;
            errdefer kernel.mm.kfree(new_inode);
            var new_dentry = try fs.DEntry.alloc(_name, sb, new_inode);
            errdefer kernel.mm.kfree(new_dentry);
            parent.tree.addChild(&new_dentry.tree);
            parent.ref.ref();
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
        const sb: *fs.SuperBlock = if (base.sb != null) base.sb.? else return kernel.errors.PosixError.EINVAL;
        if (!base.mode.isDir())
            return error.NotDirectory;
        if (!base.mode.canWrite(base.uid, base.gid))
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            const new_inode = try DevInode.new(sb);
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

    fn unlink(_dentry: *fs.DEntry) !void {
        const sb = if (_dentry.inode.sb) |_s| _s else
            return kernel.errors.PosixError.EINVAL;
        if (_dentry.inode.mode.isDir())
            return kernel.errors.PosixError.EISDIR;
        const dev_inode = _dentry.inode.getImpl(DevInode, "base");

        kernel.logger.DEBUG("unlink {d}", .{_dentry.ref.getValue()});
        if (_dentry.tree.hasChildren() or _dentry.ref.getValue() > 2)
            return kernel.errors.PosixError.EBUSY;
        _dentry.ref.unref();
        if (_dentry.tree.parent) |_p| {
            const _parent = _p.entry(fs.DEntry, "tree");
            const key = fs.DentryHash{
                .sb = @intFromPtr(sb),
                .ino = _parent.inode.i_no,
                .name = _dentry.name
            };
            _ = fs.dcache.remove(key);
            _ = sb.inode_map.remove(_dentry.inode.i_no);
            _parent.ref.unref();
        }
        dev_inode.deinit();
        _dentry.release();
    }

    fn deinit(self: *DevInode) void {
        kernel.mm.kfree(self);
    }
};

var dev_inode_ops = fs.InodeOps {
    .create = DevInode.create,
    .mknod = DevInode.mknod,
    .unlink = DevInode.unlink,
    .lookup = DevInode.lookup,
    .mkdir = DevInode.mkdir,
    .get_link = null,
};
