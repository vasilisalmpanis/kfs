const fs = @import("fs.zig");
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
    }

    pub fn getImpl(base: *Inode, comptime T: type, comptime member: []const u8) *T {
        return @fieldParentPtr(member, base);
    }
};

// TODO: define the Inode Ops struct with documentation.
pub const InodeOps = struct {
    file_ops: *const fs.FileOps,
    create: *const fn(base: *Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) anyerror!*fs.DEntry,
    lookup: *const fn (base: *Inode, name: []const u8) anyerror!*fs.DEntry,
    mkdir: *const fn (base: *Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) anyerror!*fs.DEntry,
};
