const FileSystem = @import("../fs-type.zig").FileSystem;
const lst = @import("../../utils/list.zig");
const kernel = @import("../../main.zig");

pub fn init_example() void {
    example_fs.register();
    example_fs2.register();
    kernel.logger.INFO("example fs initialized\n", .{});
    example_fs2.unregister();
    kernel.logger.INFO("example fs  2 unregistered\n", .{});
}

var example_fs: FileSystem = FileSystem{
    .name = "examplefs",
    .list = .{ .next = &example_fs.list , .prev = &example_fs.list},
    .sbs = .{ .next = &example_fs.sbs , .prev = &example_fs.sbs},
};

var example_fs2: FileSystem = FileSystem{
    .name = "examplefs2",
    .list = .{ .next = &example_fs.list , .prev = &example_fs.list},
    .sbs = .{ .next = &example_fs.sbs , .prev = &example_fs.sbs},
};
