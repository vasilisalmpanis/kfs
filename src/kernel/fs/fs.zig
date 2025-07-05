pub const kernel = @import("../main.zig");
// SuperBlock
pub const SuperBlock = @import("./super.zig").SuperBlock;
pub const SuperOps = @import("super.zig").SuperOps;
// Mount
pub const Mount = @import("mount.zig").Mount;
pub const mount = @import("mount.zig");

// DEntry
pub const DEntry = @import("dentry.zig").DEntry;
pub const init_cache = @import("dentry.zig").init_cache;

// Filesystem
pub const filesystem = @import("filesystem.zig");
pub const FileSystem = filesystem.FileSystem;
pub const FileSystemOps = filesystem.FileSystemOps;

// Inode
pub const Inode = @import("inode.zig").Inode;
pub const InodeOps = @import("inode.zig").InodeOps;

// Utils
pub const Refcount = @import("../sched/task.zig").RefCount;
pub const TreeNode = @import("../utils/tree.zig").TreeNode;
pub const list = kernel.list;

pub var last_ino: u32 = 0;
var last_ino_lock = kernel.Mutex.init();

pub fn get_ino() u32 {
    last_ino_lock.lock();
    defer last_ino_lock.unlock();
    const tmp = last_ino;
    last_ino += 1;
    return tmp;
}



pub const UMode = struct {
    grp: u4 = 0,
    usr: u4 = 0,
    other: u4 = 0,
    _unsed: u4 = 0
};

pub const Path = struct {
    mnt: *Mount,
    dentry: *DEntry,
};

pub const FSInfo = struct {
    root: Path,
    pwd: Path,

    pub fn alloc() !*FSInfo {
        if (kernel.mm.kmalloc(FSInfo)) |_fs| {
            return _fs;
        }
        return error.OutOfMemory;
    }

    pub fn clone(self: *FSInfo) !*FSInfo {
        const _fs = try FSInfo.alloc();
        _fs.* = self.*;
        return _fs;
    }
};
