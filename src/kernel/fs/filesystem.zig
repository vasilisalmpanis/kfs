const fs = @import("fs.zig");
const list = fs.list;
const Mutex = @import("../sched/mutex.zig").Mutex;
const std = @import("std");

pub var filesystem_mutex: Mutex = Mutex.init(); 
pub var fs_list: ?*FileSystem = null;

pub const FileSystem = struct {
    name: []const u8,
    list: list.ListHead,
    sbs: list.ListHead,

    // TODO: define and document FileSystemOps
    ops: *const FileSystemOps,

    pub fn init(
        name: []const u8,
    ) FileSystem {
        var _fs = FileSystem{
            .name = name,
            .list = list.ListHead.init(),
            .sbs = list.ListHead.init(),
        };
        _fs.list.setup();
        _fs.sbs.setup();
        return fs;
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
};

pub const FileSystemOps = struct {
    getSB: * const fn (source: []const u8) anyerror!*fs.SuperBlock,
};
