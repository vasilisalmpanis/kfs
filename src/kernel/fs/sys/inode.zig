const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const drv = @import("drivers");


pub const SysInode = struct {
    base: fs.Inode,
    buff: [50]u8,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(SysInode)) |inode| {
            inode.base.dev_id = drv.device.dev_t{
                .major = 0,
                .minor = 0,
            };
            inode.base.setup(sb);
            inode.base.ops = &sys_inode_ops;
            inode.base.fops = &file.SysFileOps;
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
        const sb = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (kernel.mm.dupSlice(u8, name)) |_name| {
            var cash_key = fs.DentryHash{
                .sb = @intFromPtr(parent.sb),
                .ino = base.i_no,
                .name = _name,
            };
            if (fs.dcache.get(cash_key)) |_| {
                return error.Exists;
            }
            var new_inode = try SysInode.new(sb);
            new_inode.setCreds(
                kernel.task.current.uid,
                kernel.task.current.gid,
                mode
            );
            new_inode.mode.type |= kernel.fs.S_IFDIR;
            new_inode.links = 2;
            errdefer kernel.mm.kfree(new_inode);
            var new_dentry = try fs.DEntry.alloc(_name, sb, new_inode);
            errdefer kernel.mm.kfree(new_dentry);
            parent.inode.links += 1;
            parent.tree.addChild(&new_dentry.tree);
            parent.ref.ref();
            cash_key.name = new_dentry.name;
            try fs.dcache.put(cash_key, new_dentry);
            return new_dentry;
        } else {
            return error.OutOfMemory;
        }
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        const sb = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (!base.mode.isDir())
            return error.NotDirectory;
        if (!base.mode.canWrite(base.uid, base.gid))
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            const new_inode = try SysInode.new(sb);
            errdefer kernel.mm.kfree(new_inode);
            new_inode.setCreds(
                kernel.task.current.uid,
                kernel.task.current.gid,
                mode
            );
            var dent = try parent.new(name, new_inode);
            dent.ref.ref();
            if (mode.isDir())
                base.links += 1;
            return dent;
        };
        return error.Exists;
    }

    fn unlink(_: *fs.Inode, _dentry: *fs.DEntry) !void {
        _ = if (_dentry.inode.sb) |_s| _s else
            return kernel.errors.PosixError.EINVAL;

        if (_dentry.inode.mode.isDir())
            return kernel.errors.PosixError.EISDIR;

        if (_dentry.tree.hasChildren() or _dentry.ref.getValue() > 2)
            return kernel.errors.PosixError.EBUSY;

        _dentry.inode.links -= 1;
        _dentry.release();
        _dentry.release();
    }

    pub fn deinit(self: *SysInode) void {
        if (self.base.links == 0) {
            kernel.mm.kfree(self);
        }
    }
};

const sys_inode_ops = fs.InodeOps {
    .create = SysInode.create,
    .mknod = null,
    .unlink = SysInode.unlink,
    .lookup = SysInode.lookup,
    .mkdir = SysInode.mkdir,
    .get_link = null,
};
