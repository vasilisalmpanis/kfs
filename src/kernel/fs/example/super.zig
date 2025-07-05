const fs = @import("../fs.zig");
const FileSystem = fs.FileSystem;
const lst = fs.list;
const kernel = fs.kernel;

pub fn init_example() void {
    example_fs.list.setup();
    example_fs.sbs.setup();
    example_fs.register();
    kernel.logger.INFO("example fs initialized\n", .{});
}

fn kill_sb(self: *kernel.task.RefCount) void {
    const sb: *fs.SuperBlock = lst.containerOf(fs.SuperBlock, @intFromPtr(self), "ref");
    kernel.mm.kfree(sb);
}

fn getSB(source: []const u8) !*fs.SuperBlock {
    if (!example_fs.sbs.isEmpty()) {
        const sb = example_fs.sbs.entry(fs.SuperBlock, "list");
        return sb;
    } else {
        // alloc
        if (kernel.mm.kmalloc(fs.SuperBlock)) |sb| {
            const root_inode = fs.Inode.alloc() catch |err| {
                kernel.mm.kfree(sb);
                return err;
            };
            _ = root_inode;
            _ = source;
            const dntry = fs.DEntry.alloc("/", sb) catch {
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
    .ops = &example_fs_ops,
};

pub var example_fs_ops: fs.FileSystemOps = fs.FileSystemOps {
    .getSB = getSB,
};
