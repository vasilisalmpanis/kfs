const fs = @import("../fs.zig");
const FileSystem = fs.FileSystem;
const lst = fs.list;
const kernel = fs.kernel;
const super = @import("super.zig");
const device = @import("drivers").device;

pub fn init() void {
    if (kernel.mm.kmalloc(Ext2FileSystem)) |_fs| {
        _fs.base.setup("ext2", &ext2_fs_ops);
        _fs.base.virtual = false;
    }
    kernel.logger.INFO("ext2 filesystem initialized\n", .{});
}

pub const Ext2FileSystem = struct {
    base: fs.FileSystem,


    fn getSB(base: *fs.FileSystem, dev_file: ?*fs.File) !*fs.SuperBlock {
        if (dev_file) |file| {
            const self: *Ext2FileSystem = base.getImpl(Ext2FileSystem, "base");
            if (!self.base.sbs.isEmpty()) {
                kernel.logger.INFO("sb already exists\n", .{});
                const sb = self.base.sbs.next.?.entry(fs.SuperBlock, "list");
                if (sb.dev_file.?.inode.dev_id == dev_file.?.inode.dev_id) {
                    sb.ref.ref();
                    return sb;
                }
            }
            const sb: *fs.SuperBlock = super.Ext2Super.create(base, file) catch |err| {
                return err;
            };
            sb.ref.ref();
            // here
            return sb;
        } else {
            return kernel.errors.PosixError.ENODEV;
        }
    }
};

pub var ext2_fs_ops: fs.FileSystemOps = fs.FileSystemOps {
    .getSB = Ext2FileSystem.getSB,
};
