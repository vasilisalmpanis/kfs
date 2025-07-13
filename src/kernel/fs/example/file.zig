const fs = @import("../fs.zig");

pub const ExampleFile = struct {
    base: fs.File,

    fn open(_: *fs.File, _: *fs.Inode) !void {
    }
};

pub const ExampleFileOps: fs.FileOps = fs.FileOps {
    .open = ExampleFile.open,
};
