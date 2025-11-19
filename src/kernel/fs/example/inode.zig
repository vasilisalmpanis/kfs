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
            return error.Exists;
        }
        var new_inode = try ExampleInode.new(sb);
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

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        const sb: *fs.SuperBlock = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (!base.mode.isDir())
            return kernel.errors.PosixError.ENOTDIR;
        if (!base.mode.canWrite(base.uid, base.gid))
            return kernel.errors.PosixError.EACCES;


        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            const new_inode = try ExampleInode.new(sb);
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
        return kernel.errors.PosixError.EEXIST;
    }

    pub fn getLink(base: *fs.Inode, resulting_link: *[]u8) !void {
        const example_inode = base.getImpl(ExampleInode, "base");
        const span: []const u8 = std.mem.span(@as([*:0]u8, @ptrCast(&example_inode.buff)));
        if (span.len > resulting_link.len) {
            return kernel.errors.PosixError.EINVAL;
        }
        @memcpy(resulting_link.*[0..span.len], span);
        resulting_link.len = span.len;
        return ;
    }

    fn symlink(parent: *fs.DEntry, name: []const u8, target: []const u8) !void {
        const new_inode = try ExampleInode.new(parent.sb);
        errdefer kernel.mm.kfree(new_inode);
        new_inode.setCreds(
            kernel.task.current.uid,
            kernel.task.current.gid,
            fs.UMode.link()
        );
        const example_inode = new_inode.getImpl(ExampleInode, "base");
        if (target.len + 1 > example_inode.buff.len)
            return kernel.errors.PosixError.ENAMETOOLONG;
        @memset(example_inode.buff[0..example_inode.buff.len], 0);
        @memcpy(example_inode.buff[0..target.len], target);
        var dent = try parent.new(name, new_inode);
        dent.ref.ref();
    }

    fn link(parent: *fs.DEntry, name: []const u8, target: fs.path.Path) !void {
        target.dentry.inode.links += 1;
        var dent = try parent.new(name, target.dentry.inode);
        dent.ref.ref();
    }

    fn deinit(self: *ExampleInode) void {
        if (self.base.links == 1) {
            kernel.mm.kfree(self);
        } else {
            self.base.links -= 1;
        }
    }
};

const example_inode_ops = fs.InodeOps {
    .create = ExampleInode.create,
    .mknod = null,
    .lookup = ExampleInode.lookup,
    .mkdir = ExampleInode.mkdir,
    .get_link = ExampleInode.getLink,
    .symlink = ExampleInode.symlink,
    .link = ExampleInode.link,
};
