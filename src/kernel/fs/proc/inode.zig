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
        const sb: *fs.SuperBlock = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        var cash_key = fs.DentryHash{
            .sb = @intFromPtr(parent.sb),
            .ino = base.i_no,
            .name = name,
        };
        if (fs.dcache.get(cash_key)) |_| {
            return error.Exists;
        }
        var new_inode = try ProcInode.new(sb);
        new_inode.setCreds(
            kernel.task.current.uid,
            kernel.task.current.gid,
            mode
        );
        errdefer kernel.mm.kfree(new_inode);
        var new_dentry = try fs.DEntry.alloc(name, sb, new_inode);
        errdefer kernel.mm.kfree(new_dentry);
        parent.tree.addChild(&new_dentry.tree);
        parent.ref.ref();
        cash_key.name = new_dentry.name;
        try fs.dcache.put(cash_key, new_dentry);
        return new_dentry;
    }

    fn rmdir(current: *fs.DEntry, _: *fs.DEntry) !void {
        _ = if (current.inode.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (current.tree.hasChildren())
            return kernel.errors.PosixError.ENOTEMPTY;
        if (current.ref.getValue() > 2)
            return kernel.errors.PosixError.EBUSY;
        const proc_inode = current.inode.getImpl(ProcInode, "base");

        current.ref.unref();

        proc_inode.deinit();
        current.release();
        return ;
    }

    fn unlink(_dentry: *fs.DEntry) !void {
        _ = if (_dentry.inode.sb) |_s| _s else
            return kernel.errors.PosixError.EINVAL;
        if (_dentry.inode.mode.isDir())
            return kernel.errors.PosixError.EISDIR;
        const proc_inode = _dentry.inode.getImpl(ProcInode, "base");

        if (_dentry.tree.hasChildren() or _dentry.ref.getValue() > 2)
            return kernel.errors.PosixError.EBUSY;
        _dentry.ref.unref();
        proc_inode.deinit();
        _dentry.release();
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        const sb: *fs.SuperBlock = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (!base.mode.isDir())
            return error.NotDirectory;

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
            return dent;
        };
        return error.Exists;
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

    fn deinit(self: *ProcInode) void {
        kernel.mm.kfree(self);
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
};
