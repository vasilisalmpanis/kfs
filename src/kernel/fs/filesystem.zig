const fs = @import("fs.zig");
const list = fs.list;
const Mutex = @import("../sched/mutex.zig").Mutex;
const std = @import("std");
const device = @import("drivers").device;

pub var filesystem_mutex: Mutex = Mutex.init(); 
pub var fs_list: ?*FileSystem = null;

pub const FileSystem = struct {
    name: []const u8,
    list: list.ListHead,
    sbs: list.ListHead,
    virtual: bool = true,
    ops: *const FileSystemOps,

    pub fn setup(
        self: *FileSystem,
        name: []const u8,
        ops: *FileSystemOps,
    ) void {
        self.list.setup();
        self.sbs.setup();
        self.name = name;
        self.ops = ops;
        self.virtual = true;
        self.register();
    }

    pub fn register(_fs: *FileSystem) void {
        filesystem_mutex.lock();
        defer filesystem_mutex.unlock();
        if (fs_list) |head| {
            head.list.add(&_fs.list);
        } else {
            fs_list = _fs;
        }
    }

    pub fn unregister(_fs: *FileSystem) void {
        filesystem_mutex.lock();
        defer filesystem_mutex.unlock();
        if (fs_list) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                var fs_entry = node.curr.entry(FileSystem, "list");
                if (std.mem.eql(u8, _fs.name, fs_entry.name))
                    fs_entry.list.del();
            }
        }
    }

    pub fn find(name: []const u8) ?*FileSystem {
        filesystem_mutex.lock();
        defer filesystem_mutex.unlock();
        if (fs_list) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                const _fs: *FileSystem = node.curr.entry(FileSystem, "list");
                if (std.mem.eql(u8, _fs.name, name)) {
                    return _fs;
                }
            }
        }
        return null;
    }

    pub fn getImpl(base: *FileSystem, comptime T: type, comptime member: []const u8) *T {
        return @fieldParentPtr(member, base);
    }
};

pub const FileSystemOps = struct {
    getSB: * const fn (fs: *FileSystem, dev: ?*fs.File) anyerror!*fs.SuperBlock,
};
