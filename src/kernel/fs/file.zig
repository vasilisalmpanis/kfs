const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const mount = fs.mount;
const Refcount = fs.Refcount;
const std = @import("std");
const kernel = fs.kernel;


/// File: it represents any currently open inode in the current process.
pub const File = struct {
    // ops: *FileOps,
    dentry: *DEntry,
    ref: Refcount,
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

// TODO: define and document the file operations callbacks.
// pub const FileOps = struct {
//    open: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//    release: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//    read: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//    write: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
// };
