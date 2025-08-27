const fs = @import("../fs.zig");
const FileSystem = fs.FileSystem;
const lst = fs.list;
const kernel = fs.kernel;
const super = @import("super.zig");

pub fn init() void {
    if (kernel.mm.kmalloc(ExampleFileSystem)) |_fs| {
        _fs.base.setup("examplefs", &example_fs_ops);
    }
    kernel.logger.INFO("example fs initialized\n", .{});
}

pub const ExampleFileSystem = struct {
    base: fs.FileSystem,


    fn getSB(base: *fs.FileSystem, source: []const u8) !*fs.SuperBlock {
        const self: *ExampleFileSystem = base.getImpl(ExampleFileSystem, "base");
        if (!self.base.sbs.isEmpty()) {
            kernel.logger.INFO("sb already exists\n", .{});
            const sb = self.base.sbs.next.?.entry(fs.SuperBlock, "list");
            return sb;
        } else {
            const sb: *fs.SuperBlock = super.ExampleSuper.create(base, source) catch |err| {
                return err;
            };
            return sb;
        }
    }
};


pub var example_fs_ops: fs.FileSystemOps = fs.FileSystemOps {
    .getSB = ExampleFileSystem.getSB,
};
