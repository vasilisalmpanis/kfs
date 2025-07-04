const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const mount = fs.mount;
const Refcount = fs.Refcount;


/// File: it represents any currently open inode in the current process.
pub const File = struct {
    // ops: *FileOps,
    dentry: *DEntry,
    vfsmount: *mount.VFSmount,
    ref: Refcount,
};

// TODO: define and document the file operations callbacks.
// pub const FileOps = struct {
//    open: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
//    release: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
//    read: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
//    write: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
// };
