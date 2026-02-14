const fs = @import("fs.zig");
const drv = @import("drivers");
const Refcount = fs.Refcount;
const kernel = fs.kernel;
const UMode = fs.UMode;
const Socket = @import("../net/socket.zig").Socket;

/// Inode: Represents an object in the filesystem.
/// only one copy of a specific inode exists at every point
/// in time but each inode can have multiple dentries.
pub const Inode = struct {
    i_no: u32 = 0,
    sb: ?*fs.SuperBlock,
    ref: Refcount = Refcount.init(),
    mode: fs.UMode = fs.UMode{},
    uid: u32 = 0,
    gid: u32 = 0,
    atime: u32 = 0,
    ctime: u32 = 0,
    mtime: u32 = 0,
    dev_id: drv.device.dev_t,
    data: extern union {
        dev: ?*drv.device.Device,
        sock: ?*Socket,
        pipe: ?*fs.pipe.Pipe,
    },
    size: usize = 0,
    links: u32 = 1,
    ops: *const InodeOps,
    fops: *const fs.FileOps,

    pub fn setup(
        self: *Inode,
        sb: ?*fs.SuperBlock,
    ) void {
        self.i_no = fs.get_ino();
        self.sb = sb;
        self.ref = Refcount.init();
        self.ref.ref();
        self.size = 0;
        self.mode = UMode{};
        self.data.dev = null;
        self.data.sock = null;
        self.uid = 0;
        self.gid = 0;
        self.atime = 0;
        self.ctime = 0;
        self.mtime = 0;
        self.links = 1;
        self.dev_id = drv.device.dev_t {
            .minor = 0,
            .major = 0,
        };
    }

    pub fn allocEmpty() !*Inode{
        if (kernel.mm.kmalloc(Inode)) |node| {
            node.setup(null);
            return node;
        }
        return kernel.errors.PosixError.ENOMEM;
    }

    pub fn setCreds(self: *Inode, uid: u32, gid: u32, mode: fs.UMode) void {
        self.uid = uid;
        self.gid = gid;
        self.mode = mode;
    }

    pub fn getImpl(base: *Inode, comptime T: type, comptime member: []const u8) *T {
        return @fieldParentPtr(member, base);
    }

    pub fn setup_special(inode: *Inode) void {
        switch (inode.mode) {
            fs.S_IFCHR => {
                inode.fops = &drv.cdev.cdev_default_ops;
            },
            fs.S_IFBLK => {@panic("todo");},
            else => {},
        }
    }

    pub fn canRead(self: *Inode) bool {
        return self.mode.canRead(self.uid, self.gid);
    }

    pub fn canWrite(self: *Inode) bool {
        return self.mode.canWrite(self.uid, self.gid);
    }

    pub fn canExecute(self: *Inode) bool {
        return self.mode.canExecute(self.uid, self.gid);
    }

    pub fn canAccess(self: *Inode, flags: u32) bool {
        if (kernel.task.current.uid == 0) {
            return true;
        }
        if (((flags & 0b11 == 0) and self.canRead()))
            return true;
        if (flags & fs.file.O_WRONLY != 0 and self.canWrite())
            return true;
        if (flags & fs.file.O_RDWR != 0 and self.canRead() and self.canWrite())
            return true;
        return false;
    }

    pub fn setattr(base: *fs.Inode, attr: *const InodeAttrs) !void {
        if (attr.mode) |new_mode| {
            base.mode.copyPerms(new_mode.*);
        }
        if (attr.gid) |_gid| {
            base.gid = _gid;
        }
        if (attr.uid) |_uid| {
            base.uid = _uid;
        }
        if (attr.atime) |_atime| {
            var to_set: u32 = @intCast(_atime.tv_sec);
            if (_atime.isNow()) {
                to_set = @intCast(kernel.cmos.toUnixSeconds(kernel.cmos));
            } else if (_atime.isOmit()) {
                to_set = base.atime;
            }
            base.atime = to_set;
        }
        if (attr.mtime) |_mtime| {
            var to_set: u32 = @intCast(_mtime.tv_sec);
            if (_mtime.isNow()) {
                to_set = @intCast(kernel.cmos.toUnixSeconds(kernel.cmos));
            } else if (_mtime.isOmit()) {
                to_set = base.mtime;
            }
            base.mtime = to_set;
        }
    }
};

pub const InodeAttrs = struct {
    mode: ?*fs.UMode = null,
    uid: ?u32 = null,
    gid: ?u32 = null,
    atime: ?*kernel.kernel_timespec = null,
    mtime: ?*kernel.kernel_timespec = null,
};

// TODO: define the Inode Ops struct with documentation.
pub const InodeOps = struct {
    create:   *const  fn(base: *Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry)                         anyerror!*fs.DEntry,
    mkdir:    *const  fn(base: *Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode)                         anyerror!*fs.DEntry,
    lookup:   *const  fn(parent: *fs.DEntry, name: []const u8)                                                       anyerror!*fs.DEntry,
    mknod:    ?*const fn(base: *Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry, dev: drv.device.dev_t)  anyerror!*fs.DEntry,
    get_link: ?*const fn(base: *Inode, res_link: *[:0]u8)                                                            anyerror!void,
    unlink:   ?*const fn(parent: *fs.Inode, dentry: *fs.DEntry)                                                      anyerror!void  = null,
    rmdir:    ?*const fn(current: *fs.DEntry, parent: *fs.DEntry)                                                    anyerror!void  = null,
    symlink:  ?*const fn(parent: *fs.DEntry, name: []const u8, target: []const u8)                                   anyerror!void  = null,
    link:     ?*const fn(parent: *fs.DEntry, name: []const u8, target: fs.path.Path)                                 anyerror!void  = null,
    readlink: ?*const fn(base: *fs.Inode, buf: [*]u8, size: u32)                                                     anyerror!u32   = null,
    rename:   ?*const fn(old_parent: *fs.DEntry, old: *fs.DEntry, new_parent: *fs.DEntry, new_name: []const u8)      anyerror!void  = null,
    setattr:  ?*const fn(base: *fs.Inode, attr: *const InodeAttrs)                                                   anyerror!void  = Inode.setattr,
};
