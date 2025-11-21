const fs = @import("../fs.zig");
const kernel = fs.kernel;
const DevInode = @import("inode.zig").DevInode;
const std = @import("std");
const device = @import("drivers").device;

const DEVFS_MAGIC = 0x1373;

pub const DevSuper = struct {
    base: fs.SuperBlock,

    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
        return error.NotImplemented;
    }

    pub fn create(_fs: *fs.FileSystem, dev: ?*fs.File) !*fs.SuperBlock {
        if (kernel.mm.kmalloc(DevSuper)) |sb| {
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            sb.base.block_size = 0;
            sb.base.magic = DEVFS_MAGIC;
            sb.base.dev_file = null;
            const root_inode = DevInode.new(&sb.base) catch |err| {
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
            sb.base.ops = &dev_super_ops;
            _fs.sbs.add(&sb.base.list);
            return &sb.base;
        }
        return error.OutOfMemory;
    }

    fn destroyInode(self: *fs.SuperBlock, base: *fs.Inode) !void {
        _ = self.inode_map.remove(base.i_no);
        const dev_inode = base.getImpl(DevInode, "base");
        dev_inode.deinit();
    }
};

const dev_super_ops = fs.SuperOps{
    .alloc_inode = DevSuper.allocInode,
    .destroy_inode = DevSuper.destroyInode,
};
