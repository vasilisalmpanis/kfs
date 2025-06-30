const lst = @import("../utils/list.zig");
const vfs = @import("./vfs.zig");
const mutex = @import("../sched/mutex.zig");

pub var mnt_list = lst.ListHead{
    .next = &mnt_list,
    .prev = &mnt_list,
};

// Root fs is passed as a parameter from the boot loader.
// This will be mountpoint '/' all others are children
// of this.

pub var mnt_lock = mutex.Mutex.init();

pub const Mount = struct {

    list: lst.ListHead,

    pub fn add(mount: *Mount) void {
        mnt_lock.lock();
        defer mnt_lock.unlock();
        mnt_list.add(&mount.list);
    }

    pub fn erase(mount: *Mount) void {
        mnt_lock.lock();
        defer mnt_lock.unlock();
        var it = mnt_list.iterator();
        while (it.next()) |node| {
            if (node.curr == &mount.list) {
                node.curr.del();
                return ;
            }
        }
    }
};

pub const VFSMount = struct {
    mnt_root: *vfs.DEntry,
    sb: *vfs.SuperBlock,
};
