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

    fn lookup(_: *fs.Inode) !*fs.DEntry {
        return error.InodeNotFound;
    }

    fn mkdir(base: *fs.Inode, parent: fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        var new_inode = try ExampleInode.create(base.sb);
        var new_dentry = fs.DEntry.alloc(name, base.sb) catch |err| {
            kernel.mm.kfree(new_inode);
            return err;
        };
        new_dentry.inode = new_inode;
        parent.tree.addChild(&new_dentry.tree);
        new_inode.mode = mode;
        
    }
};

const example_inode_ops = fs.InodeOps {
    .lookup = ExampleInode.lookup,
    .mkdir = ExampleInode.mkdir,
};
