const lst = @import("../utils/list.zig");
const Mutex = @import("../sched/mutex.zig").Mutex;
const std = @import("std");

pub var filesystem_mutex: Mutex = Mutex.init(); 
pub var fs_list: ?*FileSystem = null;

pub const FileSystem = struct {
    name: []const u8,
    list: lst.ListHead,
    sbs: lst.ListHead,

    // mount: ?* const fn () void,
    // destroy_sb: ?* const fn () void,
    // init_fs: ?* const fn () void,

    pub fn init(
        name: []const u8,
    ) FileSystem {
        var fs = FileSystem{
            .name = name,
            .list = lst.ListHead.init(),
            .sbs = lst.ListHead.init(),
        };
        fs.list.setup();
        fs.sbs.setup();
        return fs;
    }

    pub fn register(fs: *FileSystem) void {
        filesystem_mutex.lock();
        defer filesystem_mutex.unlock();
        if (fs_list) |head| {
            head.list.add(&fs.list);
        } else {
            fs_list = fs;
        }
    }

    pub fn unregister(fs: *FileSystem) void {
        filesystem_mutex.lock();
        defer filesystem_mutex.unlock();
        if (fs_list) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                var fs_entry = node.curr.entry(FileSystem, "list");
                if (std.mem.eql(u8, fs.name, fs_entry.name))
                    fs_entry.list.del();
            }
        }
    }
};
