const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");
const krn = @import("../main.zig");
const fs = @import("fs.zig");

pub var mountpoints: ?*Mount = null;

// Root fs is passed as a parameter from the boot loader.
// This will be mountpoint '/'. All others are children
// of this.

pub var mnt_lock = mutex.Mutex.init();

// TODO: mount cache for faster lookup.

pub const Mount = struct {
    sb: *fs.SuperBlock,
    root: *fs.DEntry,
    list: lst.ListHead,

    pub fn find(target: *fs.DEntry) ?*Mount {
        mnt_lock.lock();
        defer mnt_lock.unlock();
        if (mountpoints) |point| {
            var it = point.list.iterator();
            while (it.next()) |node| {
                const mnt: *Mount = node.curr.entry(Mount, "list");
                krn.logger.INFO("target : {x} point : {x}\n", .{
                    @intFromPtr(target),
                    @intFromPtr(mnt.root),
                });
                if (mnt.root == target) {
                    return mnt;
                }
            }
        }
        return null;
    }

    pub fn add(mnt: *Mount) void {
        mnt_lock.lock();
        defer mnt_lock.unlock();
        if (mountpoints) |_root| {
            _root.list.add(&mnt.list);
        } else {
            mountpoints = mnt;
        }
    }

    pub fn erase(mnt: *Mount) void {
        mnt_lock.lock();
        defer mnt_lock.unlock();
        if (mountpoints) |_root| {
            var it = _root.list.iterator();
            while (it.next()) |node| {
                if (node.curr == &mnt.list) {
                    if (node.curr.isEmpty()) {
                        mountpoints = null;
                    } else {
                        node.curr.del();
                    }
                    return;
                }
            }
        }
    }

    pub fn mount(
        source: []const u8,
        target: []const u8,
        fs_type: *fs.FileSystem) !*Mount {
        var curr: *fs.DEntry = undefined;
        const sb: *fs.SuperBlock = try fs_type.ops.getSB(fs_type, source);
        errdefer sb.ref.unref();
        if (mountpoints != null) {
            var last: []const u8 = "";
            const point = fs.path.remove_trailing_slashes(target);
            curr = try fs.path.dir_resolve(point, &last);
            if (last.len != 0) {
                curr = try curr.inode.ops.lookup(curr.inode, last);
                krn.logger.INFO("name {s}\n", .{curr.name});
            }
        } else {
            curr = fs.DEntry.alloc(target, sb, sb.root.inode) catch {
                return error.OutOfMemory;
            };
            errdefer curr.release();
        }
        if (krn.mm.kmalloc(Mount)) |mnt| {
            mnt.root = curr;
            mnt.sb = sb;
            mnt.list.setup();
            mnt.add();
            return mnt;
        } else {
            sb.ref.unref(); // later maybe something else
            return error.OutOfMemory;
        }
    }
};

pub const VFSMount = struct {
    mnt_root: *fs.DEntry,
    sb: *fs.SuperBlock,
};
