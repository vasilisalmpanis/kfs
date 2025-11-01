// Memory
pub export const kmalloc = @import("memory.zig").kmalloc;
pub export const kfree = @import("memory.zig").kfree;
pub export const vmalloc = @import("memory.zig").vmalloc;
pub export const vfree = @import("memory.zig").vfree;

// Devices


// Kthread
pub export const kthreadCreate = @import("kthread.zig").kthreadCreate;
pub export const kthreadStop = @import("kthread.zig").kthreadStop;

pub const load_module = @import("./loader.zig").load_module;
pub const removeModule = @import("./loader.zig").removeModule;
pub const loader = @import("loader.zig");

pub const arch = @import("arch");
pub const kernel = @import("kernel");
pub const debug = @import("debug");
pub const drivers = @import("drivers");

pub const api = @import("./api.zig");
const std = @import("std");

// mod
//
const Slice = struct {
    ptr: *anyopaque,
    len: u32,
};

fn modules_open(base: *kernel.fs.File, inode: *kernel.fs.Inode) anyerror!void {
    _ = inode;
    loader.modules_mutex.lock();
    defer loader.modules_mutex.unlock();
    if (loader.modules_list == null)
        return ;
    var size: u32 = 0;
    if (loader.modules_list) |head| {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const module = node.curr.entry(loader.Module, "list");
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
            const module = node.curr.entry(loader.Module, "list");
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
        var slice: *Slice = kernel.mm.kmalloc(Slice) orelse {
            return kernel.errors.PosixError.ENOMEM;
        };
        slice.ptr = buffer.ptr;
        slice.len = buffer.len;
        base.data = slice;
    }
}

fn modules_close(base: *kernel.fs.File) void {
    if (base.data == null)
        return ;
    const buffer: *[]const u8 = @ptrCast(@alignCast(base.data));
    kernel.mm.kfree(buffer.ptr);
    kernel.mm.kfree(base.data.?);
}

fn modules_write(_: *kernel.fs.File, _: [*]const u8, _: u32) anyerror!u32 {
    return kernel.errors.PosixError.ENOSYS;
}

fn modules_read(base: *kernel.fs.File, buf: [*]u8, size: u32) anyerror!u32 {
    if (base.data == null)
        return 0;
    const buffer: *[]const u8 = @ptrCast(@alignCast(base.data));
    const current_pos: u32 = base.pos;
    if (current_pos >= buffer.len)
        return 0;
    var to_read: u32 = size;
    if (current_pos + to_read >= buffer.len) {
        to_read = buffer.len - current_pos;
    }
    @memcpy(buf[current_pos..current_pos + to_read], buffer.*[current_pos..current_pos + to_read]);
    base.pos += to_read;
    return to_read;
}

const modules_ops = kernel.fs.FileOps{
    .open = modules_open,
    .read = modules_read,
    .write = modules_write,
    .close = modules_close,
};

pub fn init() !void {
    api.init();
    const mode = kernel.fs.UMode{
        .usr = 4,
        .grp = 4,
        .other = 4,
        .type = kernel.fs.S_IFREG,
    };
    _ = try kernel.fs.procfs.createFile(kernel.fs.procfs.root, "modules", &modules_ops, mode);
}
