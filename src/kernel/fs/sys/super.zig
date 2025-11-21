const fs = @import("../fs.zig");
const kernel = fs.kernel;
const SysInode = @import("inode.zig").SysInode;
const std = @import("std");
const device = @import("drivers").device;

const SYSFS_MAGIC = 0x62656572;

pub const SysSuper = struct {
    base: fs.SuperBlock,

    pub fn allocInode(_: *fs.SuperBlock) !*fs.Inode {
        return error.NotImplemented;
    }

    pub fn create(_fs: *fs.FileSystem, dev: ?*fs.File) !*fs.SuperBlock {
        if (kernel.mm.kmalloc(SysSuper)) |sb| {
            sb.base.inode_map = std.AutoHashMap(u32, *fs.Inode).init(kernel.mm.kernel_allocator.allocator());
            sb.base.block_size = 0;
            sb.base.magic = SYSFS_MAGIC;
            sb.base.dev_file = null;
            const root_inode = SysInode.new(&sb.base) catch |err| {
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
            sb.base.ops = &sys_super_ops;
            _fs.sbs.add(&sb.base.list);
            return &sb.base;
        }
        return error.OutOfMemory;
    }

    fn destroyInode(self: *fs.SuperBlock, base: *fs.Inode) !void {
        _ = self.inode_map.remove(base.i_no);
        const sys_inode = base.getImpl(SysInode, "base");
        sys_inode.deinit();
    }
};

const sys_super_ops = fs.SuperOps{
    .alloc_inode = SysSuper.allocInode,
    .destroy_inode = SysSuper.destroyInode,
};
