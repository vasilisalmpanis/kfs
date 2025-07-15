const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");


pub const ExampleInode = struct {
    base: fs.Inode,
    buff: [50]u8,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(ExampleInode)) |inode| {
            inode.base.setup(sb);
            inode.base.ops = &example_inode_ops;
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
        const cash_key = fs.DentryHash{
            .ino = base.i_no,
            .name = name,
        };
        if (fs.dcache.get(cash_key)) |_| {
            return error.Exists;
        }
        var new_inode = try ExampleInode.new(base.sb);
        new_inode.mode = mode;
        errdefer kernel.mm.kfree(new_inode);
        var new_dentry = try fs.DEntry.alloc(name, base.sb, new_inode);
        errdefer kernel.mm.kfree(new_dentry);
        parent.tree.addChild(&new_dentry.tree);
        try fs.dcache.put(cash_key, new_dentry);
        return new_dentry;
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode) !*fs.Inode {
        if (base.mode.type != fs.S_IFDIR)
            return error.NotDirectory;
        if (!base.mode.isWriteable())
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(base, name) catch {
            const new_inode = try ExampleInode.new(base.sb);
            errdefer kernel.mm.kfree(new_inode);
            new_inode.mode = mode;
            return new_inode;
        };
        return error.Exists;
    }
};

const example_inode_ops = fs.InodeOps {
    .file_ops = &file.ExampleFileOps,
    .create = ExampleInode.create,
    .lookup = ExampleInode.lookup,
    .mkdir = ExampleInode.mkdir,
};
