const FileSystem = @import("../fs-type.zig").FileSystem;
const lst = @import("../../utils/list.zig");
const kernel = @import("../../main.zig");
const vfs = @import("../vfs.zig");

pub fn init_example() void {
    example_fs.list.setup();
    example_fs.sbs.setup();
    example_fs.register();
    kernel.logger.INFO("example fs initialized\n", .{});
}

fn kill_sb(self: *kernel.task.RefCount) void {
    const sb: *vfs.SuperBlock = lst.containerOf(vfs.SuperBlock, @intFromPtr(self), "ref");
    kernel.mm.kfree(sb);
}

fn getSB(source: []const u8) !*vfs.SuperBlock {
    if (!example_fs.sbs.isEmpty()) {
        const sb = example_fs.sbs.entry(vfs.SuperBlock, "list");
        return sb;
    } else {
        // alloc
        if (kernel.mm.kmalloc(vfs.SuperBlock)) |sb| {
            const dntry = vfs.DEntry.alloc(source,sb) catch {
                kernel.mm.kfree(sb);
                return error.OutOfMemory;
            };
            sb.root = dntry;
            sb.list.setup();
            sb.ref = kernel.task.RefCount.init();
            sb.ref.dropFn = kill_sb;
            sb.fs = &example_fs;
            example_fs.sbs.add(&sb.list);
            return sb;
        }
        return error.OutOfMemory;
    }
}

pub var example_fs: FileSystem = FileSystem{
    .name = "examplefs",
    .list = .{ .next = &example_fs.list , .prev = &example_fs.list},
    .sbs = .{ .next = &example_fs.sbs , .prev = &example_fs.sbs},
    .getSB = getSB,
};
