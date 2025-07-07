const fs = @import("../fs.zig");
const kernel = fs.kernel;


pub const ExampleInode = struct {
    base: fs.Inode,

    pub fn create(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(ExampleInode)) |inode| {
            inode.base.setup(sb);
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
        var new_inode = try ExampleInode.create(base.sb);
        new_inode.mode = mode;
        var new_dentry = fs.DEntry.alloc(name, base.sb, new_inode) catch |err| {
            kernel.mm.kfree(new_inode);
            return err;
        };
        parent.tree.addChild(&new_dentry.tree);
        fs.dcache.put(fs.DentryHash{
            .ino = new_inode.i_no,
            .name = name,
        }, new_dentry);
    }
};

const example_inode_ops = fs.InodeOps {
    .lookup = ExampleInode.lookup,
    .mkdir = ExampleInode.mkdir,
};
