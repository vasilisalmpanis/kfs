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

    pub fn alloc() !*Inode {
        if (kernel.mm.kmalloc(Inode)) |node| {
            // node.setup(null);
            return node;
        }
        return error.OutOfMemory;
    }

    pub fn setup(
        self: *Inode,
        sb: *fs.SuperBlock,
    ) void {
        self.i_no = fs.get_ino();
        self.sb = sb;
        self.ref = Refcount.init();
        self.size = 0;
        self.mode = UMode{};
        self.is_dirty = false;
    }
};

// TODO: define the Inode Ops struct with documentation.
// pub const InodeOps = struct {
//     lookup: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//     readlink: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//     create: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
// };
