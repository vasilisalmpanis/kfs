const fs = @import("../fs.zig");
const FileSystem = fs.FileSystem;
const lst = fs.list;
const kernel = fs.kernel;
const super = @import("super.zig");
const device = @import("drivers").device;
const std = @import("std");
const inode = @import("inode.zig");

pub const createFile = @import("interface.zig").createFile;
pub const mkdir = @import("interface.zig").mkdir;
pub var root: *fs.DEntry = undefined;

pub fn init() void {
    if (kernel.mm.kmalloc(ProcFileSystem)) |_fs| {
        _fs.base.setup("procfs", &proc_fs_ops);
        _ = proc_fs_ops.getSB(&_fs.base, null) catch {
            kernel.logger.ERROR("Procfs super block creation failed\n", .{});
        };
    }
    kernel.logger.INFO("proc fs initialized\n", .{});
}

pub const ProcFileSystem = struct {
    base: fs.FileSystem,

    fn getSB(base: *fs.FileSystem, dev_file: ?*fs.File) !*fs.SuperBlock {
        const self: *ProcFileSystem = base.getImpl(ProcFileSystem, "base");
        if (!self.base.sbs.isEmpty()) {
            kernel.logger.INFO("sb already exists\n", .{});
            const sb = self.base.sbs.next.?.entry(fs.SuperBlock, "list");
            return sb;
        } else {
            const sb: *fs.SuperBlock = super.ProcSuper.create(base, dev_file) catch |err| {
                return err;
            };
            return sb;
        }
    }
};


pub var proc_fs_ops: fs.FileSystemOps = fs.FileSystemOps {
    .getSB = ProcFileSystem.getSB,
};
