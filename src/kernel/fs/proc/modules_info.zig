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
    if (modules.loader.modules_list == null)
        return ;
    var size: u32 = 0;
    if (modules.loader.modules_list) |head| {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const module = node.curr.entry(modules.loader.Module, "list");
            size += module.name.len;
            size += 1; // space
            size += std.fmt.count("{d}", .{module.code.len});
            size += 1; // newline
        }
        it = head.list.iterator();
        const buffer = kernel.mm.kmallocSlice(u8, size) orelse {
            return kernel.errors.PosixError.ENOMEM;
        };
        errdefer kernel.mm.kfree(buffer.ptr);
        var offset: u32 = 0;
        while (it.next()) |node| {
            const module = node.curr.entry(modules.loader.Module, "list");
            @memcpy(buffer[offset..offset + module.name.len], module.name[0..]);
            offset += module.name.len;
            buffer[offset] = ' ';
            offset += 1;
            const current_size =  std.fmt.count("{d}", .{module.code.len});
            _ = try std.fmt.bufPrint(buffer[offset..offset + current_size], "{d}", .{module.code.len});
            offset += current_size;
            buffer[offset] = '\n';
            offset += 1;
        }
        try generic_ops.assignSlice(base, buffer);
    }
}

const modules_ops = kernel.fs.FileOps{
    .open = modules_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

pub fn init() !void {
    const mode = kernel.fs.UMode{
        .usr = 4,
        .grp = 4,
        .other = 4,
        .type = kernel.fs.S_IFREG,
    };
    _ = try interface.createFile(
        fs.procfs.root,
        "modules",
        &modules_ops,
        mode
    );
}
