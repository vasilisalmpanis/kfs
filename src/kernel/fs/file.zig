const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const mount = fs.mount;
const Refcount = fs.Refcount;
const std = @import("std");
const kernel = fs.kernel;

// Mode
pub const O_ACCMODE	= 0o0000003;
pub const O_RDONLY	= 0o0000000;
pub const O_WRONLY	= 0o0000001;
pub const O_RDWR	= 0o0000002;

// Flags
pub const O_CREAT	= 0o0000100;
pub const O_EXCL	= 0o0000200;
pub const O_NOCTTY	= 0o0000400;
pub const O_TRUNC	= 0o0001000;
pub const O_APPEND	= 0o0002000;
pub const O_NONBLOCK	= 0o0004000;
pub const O_DSYNC	= 0o0010000;
pub const FASYNC	= 0o0020000;
pub const O_DIRECT	= 0o0040000;
pub const O_LARGEFILE	= 0o0100000;
pub const O_DIRECTORY	= 0o0200000;
pub const O_NOFOLLOW	= 0o0400000;
pub const O_NOATIME	= 0o1000000;
pub const O_CLOEXEC	= 0o2000000;

/// File: it represents any currently open inode in the current process.
pub const File = struct {
    mode: fs.UMode,
    flags: u16,
    ops: *const FileOps,
    inode: *fs.Inode,
    ref: Refcount,

    pub fn init(
        self: *File,
        ops: *const FileOps,
        inode: *fs.Inode,
    ) void {
        self.ops = ops;
        self.ref = kernel.task.RefCount.init();
        self.inode = inode;
    }
};

// TODO: define and document the file operations callbacks.
pub const FileOps = struct {
    open: *const fn (base: *File, inode: *fs.Inode) anyerror!void,
};

pub const TaskFiles = struct {
    map: std.DynamicBitSet,
    fds: std.AutoHashMap(u32, *File),

    pub fn new() ?*TaskFiles {
        if (kernel.mm.kmalloc(TaskFiles)) |files| {
            files.map = std.DynamicBitSet.initEmpty(kernel.mm.kernel_allocator.allocator(), 64) catch {
                kernel.mm.kfree(files);
                return null;
            }; // Bits per long
            files.fds = std.AutoHashMap(u32, *File).init(kernel.mm.kernel_allocator.allocator());
            return files;
        }
        return null;
    }

    pub fn getNextFD(self: *TaskFiles) anyerror!u32 {
        var it = self.map.iterator(.{
            .kind = .unset,
            .direction = .forward,
        });
        if (it.next()) |index| {
            self.map.set(index);
            return index;
        }
        const result = self.map.capacity(); // Look into if capacity is taken or not
        try self.map.resize(self.map.capacity() * 2 , false);
        return result;
    }

    pub fn unsetFD(self: *TaskFiles, fd: u32) void {
        if (fd < self.map.capacity()) {
            self.map.unset(fd);
        }
    }
};
