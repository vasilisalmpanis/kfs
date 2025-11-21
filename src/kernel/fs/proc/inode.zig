const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const std = @import("std");
const drv = @import("drivers");

pub const ProcInode = struct {
    base: fs.Inode,
    buff: [50]u8,
    task: ?*kernel.task.Task,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(ProcInode)) |inode| {
            inode.base.dev_id = drv.device.dev_t{
                .major = 0,
                .minor = 0,
            };
            inode.task = null;
            inode.base.setup(sb);
            inode.base.ops = &proc_inode_ops;
            inode.base.size = 50;
            inode.base.fops = &file.ProcFileOps;
            inode.buff = .{0} ** 50;
            return &inode.base;
        }
        return kernel.errors.PosixError.ENOMEM;
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
        return kernel.errors.PosixError.ENOENT;
    }

    fn mkdir(base: *fs.Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        const sb: *fs.SuperBlock = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        var cash_key = fs.DentryHash{
            .sb = @intFromPtr(parent.sb),
            .ino = base.i_no,
            .name = name,
        };
        if (fs.dcache.get(cash_key)) |_| {
            return kernel.errors.PosixError.EEXIST;
        }
        var new_inode = try ProcInode.new(sb);
        new_inode.setCreds(
            kernel.task.current.uid,
            kernel.task.current.gid,
            mode
        );
        new_inode.links = 2;
        errdefer kernel.mm.kfree(new_inode);
        var new_dentry = try fs.DEntry.alloc(name, sb, new_inode);
        errdefer kernel.mm.kfree(new_dentry);
        parent.inode.links += 1;
        parent.tree.addChild(&new_dentry.tree);
        parent.ref.ref();
        cash_key.name = new_dentry.name;
        try fs.dcache.put(cash_key, new_dentry);
        return new_dentry;
    }

    fn rmdir(current: *fs.DEntry, parent: *fs.DEntry) !void {
        _ = if (current.inode.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (current.tree.hasChildren())
            return kernel.errors.PosixError.ENOTEMPTY;
        if (current.ref.getValue() > 2)
            return kernel.errors.PosixError.EBUSY;

        parent.inode.links -= 1;
        current.release();
        current.release();
    }

    fn unlink(_: *fs.Inode, _dentry: *fs.DEntry) !void {
        _ = if (_dentry.inode.sb) |_s| _s else
            return kernel.errors.PosixError.EINVAL;
        if (_dentry.inode.mode.isDir())
            return kernel.errors.PosixError.EISDIR;

        if (_dentry.ref.getValue() > 2)
            return kernel.errors.PosixError.EBUSY;

        _dentry.inode.links -= 1;
        _dentry.release();
        _dentry.release();
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        const sb: *fs.SuperBlock = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (!base.mode.isDir())
            return kernel.errors.PosixError.ENOTDIR;

        // We are the kernel we can have access to this directory
        // we don't need to check. This should happen only for userspace

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            const new_inode = try ProcInode.new(sb);
            errdefer kernel.mm.kfree(new_inode);
            new_inode.setCreds(
                kernel.task.current.uid,
                kernel.task.current.gid,
                mode
            );
            var dent = try parent.new(name, new_inode);
            dent.ref.ref();
            if (mode.isDir()) {
                base.links += 1;
            }
            return dent;
        };
        return kernel.errors.PosixError.EEXIST;
    }

    pub fn getLink(base: *fs.Inode, resulting_link: *[]u8) !void {
        const proc_inode = base.getImpl(ProcInode, "base");
        const span = std.mem.span(@as([*:0]u8, @ptrCast(&proc_inode.buff)));
        if (span.len > resulting_link.len) {
            return kernel.errors.PosixError.EINVAL;
        }
        @memcpy(resulting_link.*[0..span.len], span);
        return ;
    }

    fn link(parent: *fs.DEntry, name: []const u8, target: fs.path.Path) !void {
        target.dentry.inode.links += 1;
        var dent = try parent.new(name, target.dentry.inode);
        dent.ref.ref();
    }

    pub fn deinit(self: *ProcInode) void {
        if (self.base.links == 0) {
            kernel.mm.kfree(self);
        }
    }
};

const proc_inode_ops = fs.InodeOps {
    .create = ProcInode.create,
    .mknod = null,
    .lookup = ProcInode.lookup,
    .mkdir = ProcInode.mkdir,
    .rmdir = ProcInode.rmdir,
    .unlink = ProcInode.unlink,
    .get_link = ProcInode.getLink,
    .link = ProcInode.link,
};
