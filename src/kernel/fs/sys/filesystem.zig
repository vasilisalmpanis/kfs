const fs = @import("../fs.zig");
const FileSystem = fs.FileSystem;
const lst = fs.list;
const kernel = fs.kernel;
const super = @import("super.zig");
const device = @import("drivers").device;


pub fn init() void {
    if (kernel.mm.kmalloc(SysFileSystem)) |_fs| {
        _fs.base.setup("sysfs", &sys_fs_ops);
    }
    kernel.logger.INFO("sysfs initialized\n", .{});
}

pub const SysFileSystem = struct {
    base: fs.FileSystem,


    fn getSB(base: *fs.FileSystem, dev_file: ?*fs.File) !*fs.SuperBlock {
        const self: *SysFileSystem = base.getImpl(SysFileSystem, "base");
        if (!self.base.sbs.isEmpty()) {
            kernel.logger.INFO("sb already exists\n", .{});
            const sb = self.base.sbs.next.?.entry(fs.SuperBlock, "list");
            return sb;
        } else {
            const sb: *fs.SuperBlock = super.SysSuper.create(base, dev_file) catch |err| {
                return err;
            };
            return sb;
        }
    }
};


pub var sys_fs_ops: fs.FileSystemOps = fs.FileSystemOps {
    .getSB = SysFileSystem.getSB,
};
