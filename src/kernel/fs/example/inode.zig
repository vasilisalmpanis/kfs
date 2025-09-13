const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const std = @import("std");
const drv = @import("drivers");


pub const ExampleInode = struct {
    base: fs.Inode,
    buff: [50]u8,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(ExampleInode)) |inode| {
            inode.base.dev_id = drv.device.dev_t{
                .major = 0,
                .minor = 0,
            };
            inode.base.setup(sb);
            inode.base.ops = &example_inode_ops;
            inode.base.size = 50;
            inode.base.fops = &file.ExampleFileOps;
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
        var cash_key = fs.DentryHash{
            .sb = @intFromPtr(parent.sb),
            .ino = base.i_no,
            .name = name,
        };
        if (fs.dcache.get(cash_key)) |_| {
            return error.Exists;
        }
        var new_inode = try ExampleInode.new(base.sb);
        new_inode.setCreds(
            kernel.task.current.uid,
            kernel.task.current.gid,
            mode
        );
        errdefer kernel.mm.kfree(new_inode);
        var new_dentry = try fs.DEntry.alloc(name, base.sb, new_inode);
        errdefer kernel.mm.kfree(new_dentry);
        parent.tree.addChild(&new_dentry.tree);
        cash_key.name = new_dentry.name;
        try fs.dcache.put(cash_key, new_dentry);
        return new_dentry;
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        if (!base.mode.isDir())
            return error.NotDirectory;
        if (!base.mode.canWrite(base.uid, base.gid))
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            const new_inode = try ExampleInode.new(base.sb);
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
        const example_inode = base.getImpl(ExampleInode, "base");
        const span = std.mem.span(@as([*:0]u8, @ptrCast(&example_inode.buff)));
        if (span.len > resulting_link.len) {
            return kernel.errors.PosixError.EINVAL;
        }
        @memcpy(resulting_link.*[0..span.len], span);
        return ;
    }
};

const example_inode_ops = fs.InodeOps {
    .create = ExampleInode.create,
    .mknod = null,
    .lookup = ExampleInode.lookup,
    .mkdir = ExampleInode.mkdir,
    .get_link = ExampleInode.getLink,
};
