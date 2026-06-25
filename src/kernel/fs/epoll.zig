const kernel = @import("../main.zig");
const std = @import("std");

pub const EpollEntry = struct {
    fd: i32,
    events: u32,
    data: u64,
};

pub const EpollState = struct {
    entries: std.ArrayList(EpollEntry) = undefined,

    pub fn init(self: *EpollState) !void {
        self.entries = try std.ArrayList(EpollEntry).initCapacity(
            kernel.mm.kernel_allocator.allocator(),
            4,
        );
    }

    pub fn deinit(self: *EpollState) void {
        self.entries.deinit(kernel.mm.kernel_allocator.allocator());
    }
};

pub const ops = kernel.fs.FileOps {
    .open = open,
    .close = close,
    .read =  read,
    .write = write,
    .ioctl = null,
    .poll = null,
    .lseek = null
};

pub fn open(_: *kernel.fs.File, _: *kernel.fs.Inode) !void {
    return kernel.errors.PosixError.ENOSYS;
}

pub fn close(file: *kernel.fs.File) void {
    const epoll_data: *EpollState = @ptrCast(@alignCast(file.data));
    epoll_data.deinit();
    kernel.mm.kfree(epoll_data);
}

pub fn read(_: *kernel.fs.File, _: [*]u8, _: usize) !usize {
    return kernel.errors.PosixError.ENOSYS;
}

pub fn write(_: *kernel.fs.File, _: [*]const u8, _: usize) !usize {
    return kernel.errors.PosixError.ENOSYS;
}
