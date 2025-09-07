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
pub const file = @import("file.zig");
pub const File = file.File;
pub const TaskFiles = file.TaskFiles;
pub const FileOps = file.FileOps;

pub const examplefs = @import("example/filesystem.zig");
pub const sysfs = @import("sys/filesystem.zig");
pub const devfs = @import("dev/filesystem.zig");
pub const ext2 = @import("ext2/filesystem.zig");

const std = @import("std");
pub const DentryHash = struct {
    sb: u32,
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
    99
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
pub const DT_UNKNOWN	        = 0;
pub const DT_FIFO		= 1;
pub const DT_CHR		= 2;
pub const DT_DIR		= 4;
pub const DT_BLK		= 6;
pub const DT_REG		= 8;
pub const DT_LNK		= 10;
pub const DT_SOCK		= 12;
pub const DT_WHT		= 14;

pub const Dirent = extern struct {
    ino: u32,
    off: u32,
    reclen: u16,
    name: [256]u8,
};

pub const Dirent64 = extern struct {
    ino: u64,
    off: u64,
    reclen: u16,
    type: u8,
    name: [256]u8,
};

pub const LinuxDirent = extern struct {
    ino: u32,
    off: u32,
    reclen: u16,
    type: u8,

    pub fn setType(self: *LinuxDirent, mode: UMode) void {
        switch (mode.type & S_IFMT) {
            S_IFREG => self.type = DT_REG,
            S_IFDIR => self.type = DT_DIR,
            S_IFBLK => self.type = DT_BLK,
            S_IFCHR => self.type = DT_CHR,
            S_IFLNK => self.type = DT_LNK,
            S_IFIFO => self.type = DT_FIFO,
            S_IFSOCK => self.type = DT_SOCK,
            else => self.type = DT_UNKNOWN,
        }
    }

    pub fn getName(self: *LinuxDirent) []u8 {
        const name_addr: u32 = @intFromPtr(self) + @sizeOf(LinuxDirent);
        return std.mem.span(@as([*:0]u8, @ptrFromInt(name_addr)));
    }

    pub fn verboseType(self: *LinuxDirent) u8 {
        switch (self.type) {
            DT_REG => return 'r',
            DT_DIR => return 'd',
            DT_LNK => return 'l',
            DT_CHR => return 'c',
            DT_BLK => return 'b',
            DT_FIFO => return 'f',
            DT_SOCK => return 's',
            else => {}
        }
        return 'u';
    }
};

pub const S_IFMT   = 0o170;
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

    pub fn isDir(self: *UMode) bool {
        return self.type & S_IFMT == S_IFDIR;
    }

    pub fn isLink(self: *UMode) bool {
        return self.type & S_IFMT == S_IFLNK;
    }

    pub fn isReg(self: *UMode) bool {
        return self.type & S_IFMT == S_IFREG;
    }

    pub fn isChr(self: *UMode) bool {
        return self.type & S_IFMT == S_IFCHR;
    }

    pub fn isBlk(self: *UMode) bool {
        return self.type & S_IFMT == S_IFBLK;
    }

    pub fn isFifo(self: *UMode) bool {
        return self.type & S_IFMT == S_IFIFO;
    }

    pub fn isSock(self: *UMode) bool {
        return self.type & S_IFMT == S_IFSOCK;
    }

    // Modify to add ownership
    pub fn isUReadable(self: *UMode) bool {
        return self.usr & 0o4 != 0;
    }

    pub fn isUWriteable(self: *UMode) bool {
        return self.usr & 0o2 != 0;
    }

    pub fn isUExecutable(self: *UMode) bool {
        return self.usr & 0o1 != 0;
    }

    pub fn isGReadable(self: *UMode) bool {
        return self.grp & 0o4 != 0;
    }

    pub fn isGWriteable(self: *UMode) bool {
        return self.grp & 0o2 != 0;
    }

    pub fn isGExecutable(self: *UMode) bool {
        return self.grp & 0o1 != 0;
    }

    pub fn isOReadable(self: *UMode) bool {
        return self.other & 0o4 != 0;
    }

    pub fn isOWriteable(self: *UMode) bool {
        return self.other & 0o2 != 0;
    }

    pub fn isOExecutable(self: *UMode) bool {
        return self.other & 0o1 != 0;
    }

    pub fn canRead(self: *UMode, uid: u32, gid: u32) bool {
        if (uid == 0) 
            return true;
        if (kernel.task.current.uid == uid) {
            if (self.isUReadable()) {
                return true;
            }
            return false;
        }
        if (kernel.task.current.gid == gid) {
            if (self.isGReadable()) {
                return true;
            }
            return false;
        }
        if (self.isOReadable()) {
            return true;
        }
        return false;
    }

    pub fn canWrite(self: *UMode, uid: u32, gid: u32) bool {
        if (uid == 0) 
            return true;
        if (kernel.task.current.uid == uid) {
            if (self.isUWriteable()) {
                return true;
            }
            return false;
        }
        if (kernel.task.current.gid == gid) {
            if (self.isGWriteable()) {
                return true;
            }
            return false;
        }
        if (self.isOWriteable()) {
            return true;
        }
        return false;
    }

    pub fn canExecute(self: *UMode, uid: u32, gid: u32) bool {
        if (uid == 0) 
            return true;
        if (kernel.task.current.uid == uid) {
            if (self.isUExecutable()) {
                return true;
            }
            return false;
        }
        if (kernel.task.current.gid == gid) {
            if (self.isGExecutable()) {
                return true;
            }
            return false;
        }
        if (self.isOExecutable()) {
            return true;
        }
        return false;
    }
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

pub fn init() void {
    init_cache(kernel.mm.kernel_allocator.allocator());
    examplefs.init();
    sysfs.init();
    devfs.init();
    ext2.init();
}
