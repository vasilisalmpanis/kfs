const fs = @import("../fs.zig");
const FileSystem = fs.FileSystem;
const lst = fs.list;
const kernel = fs.kernel;
const super = @import("super.zig");

pub fn init() void {
    if (kernel.mm.kmalloc(Ext2FileSystem)) |_fs| {
        _fs.base.setup("ext2", &ext2_fs_ops);
        _fs.base.virtual = false;
    }
    kernel.logger.INFO("ext2 filesystem initialized\n", .{});
}

pub const Ext2FileSystem = struct {
    base: fs.FileSystem,


    fn getSB(base: *fs.FileSystem, source: []const u8) !*fs.SuperBlock {
        const self: *Ext2FileSystem = base.getImpl(Ext2FileSystem, "base");
        if (!self.base.sbs.isEmpty()) {
            kernel.logger.INFO("sb already exists\n", .{});
            const sb = self.base.sbs.next.?.entry(fs.SuperBlock, "list");
            return sb;
        } else {
            const sb: *fs.SuperBlock = super.Ext2Super.create(base, source) catch |err| {
                return err;
            };
            return sb;
        }
    }
};

pub var ext2_fs_ops: fs.FileSystemOps = fs.FileSystemOps {
    .getSB = Ext2FileSystem.getSB,
};
