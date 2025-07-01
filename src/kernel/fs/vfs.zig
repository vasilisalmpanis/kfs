const kernel = @import("../main.zig");
const TreeNode = @import("../utils/tree.zig").TreeNode;
const mount = @import("mount.zig");
const Refcount = @import("../sched/task.zig").RefCount;


pub const IFileFields = struct {
    name: []const u8,
    size: u64,
    permissions: u16,
    fd: u32 = 0,
};

pub const IFile = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        open: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        release: *const fn (ptr: *anyopaque) anyerror!u32,
        read: *const fn (ptr: *anyopaque, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        write: *const fn (ptr: *anyopaque, buff: [*]const u8, size: u32, off: *u32) anyerror!u32,
    };

    pub fn init(ptr: anytype) IFile {
        const T = @TypeOf(ptr);
        const Ptr = switch (@typeInfo(T)) {
            .pointer => |pointer| pointer,
            else => @compileError("Expected pointer type for IFile.init"),
        };
        
        const impl = struct {
            pub fn open(pointer: *anyopaque, data: []const u8) anyerror!u32 {
                const self: T = @ptrCast(@alignCast(pointer));
                return @call(.always_inline, Ptr.child.open, .{ self, data });
            }
            
            pub fn release(pointer: *anyopaque) anyerror!u32{
                const self: T = @ptrCast(@alignCast(pointer));
                return @call(.always_inline, Ptr.child.release, .{self});
            }
            
            pub fn read(pointer: *anyopaque, buff: [*]u8, size: u32, off: *u32) anyerror!u32 {
                const self: T = @ptrCast(@alignCast(pointer));
                return @call(.always_inline, Ptr.child.read, .{ self, buff, size, off });
            }

            pub fn write(pointer: *anyopaque, buff: [*]const u8, size: u32, off: *u32) anyerror!u32 {
                const self: T = @ptrCast(@alignCast(pointer));
                return @call(.always_inline, Ptr.child.write, .{ self, buff, size, off });
            }
        };

        const vtable = &VTable{
            .open = impl.open,
            .release = impl.release,
            .write = impl.write,
            .read = impl.read,
        };

        return .{
            .ptr = ptr,
            .vtable = vtable,
        };
    }

    pub fn open(self: IFile, path: []const u8) !u32 {
        return self.vtable.open(self.ptr, path);
    }
    
    pub fn release(self: IFile) !u32 {
        return self.vtable.release(self.ptr);
    }
    
    pub fn write(self: IFile, buff: [*]const u8, size: u32, off: *u32) !u32 {
        return self.vtable.write(self.ptr, buff, size, off);
    }
    
    pub fn read(self: IFile, buff: [*]u8, size: u32, off: *u32) !u32 {
        return self.vtable.read(self.ptr, buff, size, off);
    }
};


pub const Inode = struct {
    ops: *InodeOps,
    ref: Refcount,
};

pub const DEntry = struct {
    sb: *SuperBlock,
    inode: *Inode,
    ref: Refcount,
    name: []u8,
    tree: TreeNode,

};

pub const SuperBlock = struct {
    ops: *SuperOps,
};

pub const File = struct {
    ops: *FileOps,
    dentry: *DEntry,
    vfsmount: *mount.VFSMount,
    ref: Refcount,
};

pub const FileOps = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        open: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        release: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
        read: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        write: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
    };
};

pub const InodeOps = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        lookup: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        readlink: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
        create: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // link: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // unlink: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // symlink: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // mkdir: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // rmdir: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // rename: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // setattr: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        // getattr: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
    };
};

pub const SuperOps = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        alloc_inode: *const fn (ptr: *anyopaque, data: []const u8) anyerror!u32,
        destroy_inode: *const fn (ptr: *anyopaque, inode: *Inode, file: *File) anyerror!u32,
        free_inode: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
        shutdown: *const fn (ptr: *anyopaque, file: *File, buff: [*]u8, size: u32, off: *u32) anyerror!u32,
    };
};
