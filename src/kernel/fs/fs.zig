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

// Path
pub const path = @import("path.zig");

// File
pub const File = @import("file.zig").File;
pub const TaskFiles = @import("file.zig").TaskFiles;


const std = @import("std");
pub const DentryHash = struct {
    ino: u32,
    name: []const u8,
};

pub const InoNameContext = struct {
    pub fn hash(self: @This(), val: DentryHash) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(123);
        std.hash.autoHashStrat(
            &hasher,
            val,
            .Deep
        );
        return hasher.final();
    }

    pub fn eql(self: @This(), a: DentryHash, b: DentryHash) bool {
        _ = self;
        return (a.ino == b.ino and std.mem.eql(u8, a.name, b.name));
    }
};

pub var dcache: std.HashMap(
    DentryHash,
    *DEntry,
    InoNameContext,
    50
) = undefined;

pub var last_ino: u32 = 0;
var last_ino_lock = kernel.Mutex.init();

pub fn get_ino() u32 {
    last_ino_lock.lock();
    defer last_ino_lock.unlock();
    const tmp = last_ino;
    last_ino += 1;
    return tmp;
}

pub const S_IFSOCK = 0o140;
pub const S_IFLNK  = 0o120;
pub const S_IFREG  = 0o100;
pub const S_IFBLK  = 0o060;
pub const S_IFDIR  = 0o040;
pub const S_IFCHR  = 0o020;
pub const S_IFIFO  = 0o010;
pub const S_ISUID  = 0o004;
pub const S_ISGID  = 0o002;
pub const S_ISVTX  = 0o001;

pub const UMode = packed struct {
    grp: u3 = 0,
    usr: u3 = 0,
    other: u3 = 0,
    type: u7 = 0,
};


pub const FSInfo = struct {
    root: path.Path,
    pwd: path.Path,

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
