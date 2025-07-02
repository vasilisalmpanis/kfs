const lst = @import("../utils/list.zig");
const vfs = @import("vfs.zig");
const mutex = @import("../sched/mutex.zig");
const krn = @import("../main.zig");
const fs = @import("fs-type.zig");

pub var mountpoints: ?*Mount = null;

// Root fs is passed as a parameter from the boot loader.
// This will be mountpoint '/' all others are children
// of this.

pub var mnt_lock = mutex.Mutex.init();

pub const Mount = struct {
    sb: *vfs.SuperBlock,
    root: *vfs.DEntry,
    list: lst.ListHead,

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
        fs_type: *fs.FileSystem) !void {
        const sb: *vfs.SuperBlock = try fs_type.getSB(source);
        const dntr: *vfs.DEntry = vfs.DEntry.alloc(target, sb) catch {
            // TODO: put sb
            return ;
        };
        if (krn.mm.kmalloc(Mount)) |mnt| {
            mnt.root = dntr;
            mnt.sb = sb;
            mnt.list.setup();
            mnt.add();
            // mnt.root.tree.addChild(&mnt.sb.root.tree);
        } else {
            dntr.release();
            sb.ref.unref(); // later maybe something else
        }
    }
};

pub const VFSMount = struct {
    mnt_root: *vfs.DEntry,
    sb: *vfs.SuperBlock,
};
