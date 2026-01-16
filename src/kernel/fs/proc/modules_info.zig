const fs = @import("../fs.zig");
const kernel = @import("../../main.zig");
const interface = @import("interface.zig");
const std = @import("std");
const modules = @import("modules");
const generic_ops = @import("generic_ops.zig");

const Slice = struct {
    ptr: *anyopaque,
    len: u32,
};

fn modules_open(base: *kernel.fs.File, inode: *kernel.fs.Inode) anyerror!void {
    _ = inode;

    modules.loader.modules_mutex.lock();
    defer modules.loader.modules_mutex.unlock();

    const head_opt = modules.loader.modules_list;
    if (head_opt == null)
        return;

    const head = head_opt.?;

    var size: usize = 0;
    {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const module = node.curr.entry(modules.loader.Module, "list");
            size += std.fmt.count(
                "{s} {d} 0 - Live 0x00000000\n",
                .{ module.name, module.code.len },
            );
        }
    }

    const buffer = kernel.mm.kmallocSlice(u8, size) orelse
        return kernel.errors.PosixError.ENOMEM;
    errdefer kernel.mm.kfree(buffer.ptr);

    var offset: usize = 0;
    {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const module = node.curr.entry(modules.loader.Module, "list");

            const written = try std.fmt.bufPrint(
                buffer[offset..],
                "{s} {d} 0 - Live 0x00000000\n",
                .{ module.name, module.code.len },
            );
            offset += written.len;
        }
    }

    try generic_ops.assignSlice(base, buffer);
}

const modules_ops = kernel.fs.FileOps{
    .open = modules_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

pub fn init() !void {
    const mode = kernel.fs.UMode.regular();
    _ = try interface.createFile(
        fs.procfs.root,
        "modules",
        &modules_ops,
        mode
    );
}
