const fs = @import("fs.zig");
const drv = @import("drivers");
const Refcount = fs.Refcount;
const kernel = fs.kernel;
const UMode = fs.UMode;

/// Inode: Represents an object in the filesystem.
/// only one copy of a specific inode exists at every point
/// in time but each inode can have multiple dentries.

pub const Inode = struct {
    i_no: u32 = 0,
    sb: *fs.SuperBlock,
    ref: Refcount = Refcount.init(),
    mode: fs.UMode = fs.UMode{},
    uid: u32 = 0,
    gid: u32 = 0,
    dev_id: drv.device.dev_t,
    dev: ?*drv.device.Device,
    is_dirty: bool = false,
    size: u32 = 0,
    ops: *const InodeOps,
    fops: *const fs.FileOps,

    pub fn setup(
        self: *Inode,
        sb: *fs.SuperBlock,
    ) void {
        self.i_no = fs.get_ino();
        self.sb = sb;
        self.ref = Refcount.init();
        self.ref.ref();
        self.size = 0;
        self.mode = UMode{};
        self.is_dirty = false;
        self.dev = null;
        self.uid = 0;
        self.gid = 0;
        self.dev_id = drv.device.dev_t {
            .minor = 0,
            .major = 0,
        };
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

    pub fn canAccess(self: *Inode, flags: u16) bool {
        if (kernel.task.current.uid == 0) {
            return true;
        }
        if (((flags & fs.file.O_RDONLY != 0) and self.canRead()))
            return true;
        if (flags & fs.file.O_WRONLY != 0 and self.canWrite())
            return true;
        if (flags & fs.file.O_RDWR != 0 and self.canRead() and self.canWrite())
            return true;
        return false;
    }
};

// TODO: define the Inode Ops struct with documentation.
pub const InodeOps = struct {
    create: *const fn(base: *Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) anyerror!*fs.DEntry,
    mknod: ?*const fn(base: *Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry, dev: drv.device.dev_t) anyerror!*fs.DEntry,
    lookup: *const fn (parent: *fs.DEntry, name: []const u8) anyerror!*fs.DEntry,
    mkdir: *const fn (base: *Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) anyerror!*fs.DEntry,
    get_link: ?*const fn(base: *Inode, resulting_link: *[]u8) anyerror!void,
};
