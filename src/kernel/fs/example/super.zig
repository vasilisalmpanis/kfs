const fs = @import("../fs.zig");
const kernel = fs.kernel;
const ExampleInode = @import("inode.zig").ExampleInode;
const std = @import("std");



pub const ExampleSuper = struct {
    base: fs.SuperBlock,

    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
    }

    pub fn create(_fs: *fs.FileSystem, source: []const u8) !*fs.SuperBlock {
        if (kernel.mm.kmalloc(ExampleSuper)) |sb| {
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            const root_inode = ExampleInode.create(&sb.base) catch |err| {
                kernel.mm.kfree(sb);
                return err;
            };
            sb.base.inode_map.put(root_inode.i_no, root_inode) catch |err| {
                kernel.mm.kfree(root_inode);
                kernel.mm.kfree(sb);
                return err;
            };
            _ = source;
            const dntry = fs.DEntry.alloc("/", &sb.base) catch {
                kernel.mm.kfree(sb);
                return error.OutOfMemory;
            };
            dntry.tree.setup();
            dntry.inode = root_inode;
            sb.base.root = dntry;
            sb.base.list.setup();
            sb.base.ref = kernel.task.RefCount.init();
            sb.base.fs = _fs;
            _fs.sbs.add(&sb.base.list);
            return &sb.base;
        }
        return error.OutOfMemory;
    }
};

const example_super_ops = fs.SuperOps{
    .alloc_inode = ExampleSuper.allocInode,
};
