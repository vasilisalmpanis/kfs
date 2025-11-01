// Debug
pub export const print_screen = @import("debug.zig").print_screen;
pub export const print_serial = @import("debug.zig").print_serial;

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

pub const arch = @import("arch");
pub const kernel = @import("kernel");
pub const debug = @import("debug");
pub const drivers = @import("drivers");

pub const api = @import("./api.zig");
fn modules_open(base: *kernel.fs.File, inode: *kernel.fs.Inode) anyerror!void {
    _ = base;
    _ = inode;
}

fn modules_close(base: *kernel.fs.File) void {
    _ = base;
}

fn modules_write(base: *kernel.fs.File, buf: [*]const u8, size: u32) anyerror!u32 {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
}

fn modules_read(base: *kernel.fs.File, buf: [*]u8, size: u32) anyerror!u32 {
    _ = base;
    _ = buf;
    _ = size;
    return 0;
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
