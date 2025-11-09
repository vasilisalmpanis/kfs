const fs = @import("../fs.zig");
const kernel = fs.kernel;
const ProcInode = @import("inode.zig").ProcInode;
const std = @import("std");
const device = @import("drivers").device;
const filesystem = @import("filesystem.zig");

const PROCFS_MAGIC = 0x9fa0;

pub const ProcSuper = struct {
    base: fs.SuperBlock,

    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
        return error.NotImplemented;
    }

    pub fn create(_fs: *fs.FileSystem, _: ?*fs.File) !*fs.SuperBlock {
        proc_super.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
        const root_inode = ProcInode.new(&proc_super.base) catch |err| {
            return err;
        };
        root_inode.mode = fs.UMode{
            // This should come from mount.
            .type   = fs.S_IFDIR,
            .usr    = 0o7,
            .grp    = 0o5,
            .other  = 0o5,
        };
        proc_super.base.inode_map.put(root_inode.i_no, root_inode) catch |err| {
            kernel.mm.kfree(root_inode);
            return err;
        };
        const dntry = fs.DEntry.alloc("/", &proc_super.base, root_inode) catch {
            return error.OutOfMemory;
        };
        dntry.tree.setup();
        dntry.inode = root_inode;
        filesystem.root = dntry;
        proc_super.base.root = dntry;
        proc_super.base.magic = PROCFS_MAGIC;
        proc_super.base.list.setup();
        proc_super.base.ref = kernel.task.RefCount.init();
        proc_super.base.fs = _fs;
        proc_super.base.ops = &proc_super_ops; 
        _fs.sbs.add(&proc_super.base.list);
        return &proc_super.base;
    }
};

const proc_super_ops = fs.SuperOps{
    .alloc_inode = ProcSuper.allocInode,
};

pub var proc_super = ProcSuper{
    .base = fs.SuperBlock{
        .fs = undefined,
        .block_size = 1024,
        .dev_file = null,
        .inode_map = undefined,
        .list = undefined,
        .ops = &proc_super_ops,
        .ref = kernel.task.RefCount.init(),
        .root = undefined,
        .magic = PROCFS_MAGIC,
    },
};
