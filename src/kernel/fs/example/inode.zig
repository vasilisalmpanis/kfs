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
};

const example_inode_ops = fs.InodeOps {
    .lookup = ExampleInode.lookup,
};
