const fs = @import("../fs.zig");
const kernel = fs.kernel;
const ExampleInode = @import("inode.zig").ExampleInode;
const std = @import("std");
const device = @import("drivers").device;

const EXAMPLEFS_MAGIC = 0x0187;

pub const ExampleSuper = struct {
    base: fs.SuperBlock,

    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
        return error.NotImplemented;
    }

    pub fn create(_fs: *fs.FileSystem, dev: ?*fs.File) !*fs.SuperBlock {
        if (kernel.mm.kmalloc(ExampleSuper)) |sb| {
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            sb.base.block_size = 0;
            sb.base.magic = EXAMPLEFS_MAGIC;
            sb.base.dev_file = null;
            const root_inode = ExampleInode.new(&sb.base) catch |err| {
                kernel.mm.kfree(sb);
                return err;
            };
            root_inode.mode = fs.UMode.directory();
            sb.base.inode_map.put(root_inode.i_no, root_inode) catch |err| {
                kernel.mm.kfree(root_inode);
                kernel.mm.kfree(sb);
                return err;
            };
            _ = dev;
            const dntry = fs.DEntry.alloc("/", &sb.base, root_inode) catch {
                kernel.mm.kfree(sb);
                return error.OutOfMemory;
            };
            dntry.tree.setup();
            dntry.inode = root_inode;
            sb.base.root = dntry;
            sb.base.list.setup();
            sb.base.ref = kernel.task.RefCount.init();
            sb.base.fs = _fs;
            sb.base.ops = &example_super_ops;
            _fs.sbs.add(&sb.base.list);
            return &sb.base;
        }
        return error.OutOfMemory;
    }
};

const example_super_ops = fs.SuperOps{
    .alloc_inode = ExampleSuper.allocInode,
};
