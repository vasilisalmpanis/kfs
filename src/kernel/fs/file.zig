const fs = @import("fs.zig");
const DEntry = fs.DEntry;
const mount = fs.mount;
const Refcount = fs.Refcount;
const std = @import("std");
const kernel = fs.kernel;
const errors = @import("../syscalls/error-codes.zig").PosixError;

// Mode
pub const O_ACCMODE	= 0o0000003;
pub const O_RDONLY	= 0o0000000;
pub const O_WRONLY	= 0o0000001;
pub const O_RDWR	= 0o0000002;

// Flags
pub const O_CREAT	= 0o0000100;
pub const O_EXCL	= 0o0000200;
pub const O_NOCTTY	= 0o0000400;
pub const O_TRUNC	= 0o0001000;
pub const O_APPEND	= 0o0002000;
pub const O_NONBLOCK	= 0o0004000;
pub const O_DSYNC	= 0o0010000;
pub const FASYNC	= 0o0020000;
pub const O_DIRECT	= 0o0040000;
pub const O_LARGEFILE	= 0o0100000;
pub const O_DIRECTORY	= 0o0200000;
pub const O_NOFOLLOW	= 0o0400000;
pub const O_NOATIME	= 0o1000000;
pub const O_CLOEXEC	= 0o2000000;

/// File: it represents any currently open inode in the current process.
pub const File = struct {
    mode: fs.UMode,
    flags: u16,
    ops: * const FileOps,
    pos: u32,
    inode: *fs.Inode,
    ref: Refcount,
    path: fs.path.Path,

    pub fn init(
        self: *File,
        ops: *const FileOps,
        inode: *fs.Inode,
    ) void {
        self.ops = ops;
        self.pos = 0;
        self.ref = kernel.task.RefCount.init();
        self.ref.dropFn = File.release;
        self.ref.ref();
        self.inode = inode;
    }

    pub fn release(ref: *kernel.task.RefCount) void {
        const file: *File = kernel.list.containerOf(File, @intFromPtr(ref), "ref");
        const inode: *fs.Inode = file.inode;
        file.path.dentry.ref.unref();
        file.ops.close(file);
        inode.ref.unref();
        kernel.mm.kfree(file);
    }

    pub fn new(path: fs.path.Path) !*File {
        if (kernel.mm.kmalloc(File)) |new_file| {
            new_file.init(path.dentry.inode.fops, path.dentry.inode);
            new_file.path = path;
            return new_file;
        } else {
            return error.OutOfMemory;
        }
    }
};

// TODO: define and document the file operations callbacks.
pub const FileOps = struct {
    open: *const fn (base: *File, inode: *fs.Inode) anyerror!void,
    close: *const fn(base: *File) void,
    write: *const fn (base: *File, buf: [*]const u8, size: u32) anyerror!u32,
    read: *const fn (base: *File, buf: [*]u8, size: u32) anyerror!u32,
    lseek: ?*const fn (base: *File, offset: u32, origin: u32) anyerror!u32 = null,
    readdir: ?*const fn (base: *File, buf: []u8) anyerror!u32 = readdirVFS,
};

pub const TaskFiles = struct {
    map: std.DynamicBitSet,
    fds: std.AutoHashMap(u32, *File),

    pub fn new() ?*TaskFiles {
        if (kernel.mm.kmalloc(TaskFiles)) |files| {
            files.map = std.DynamicBitSet.initEmpty(kernel.mm.kernel_allocator.allocator(), 64) catch {
                kernel.mm.kfree(files);
                return null;
            }; // Bits per long
            files.fds = std.AutoHashMap(u32, *File).init(kernel.mm.kernel_allocator.allocator());
            return files;
        }
        return null;
    }

    pub fn dup(self: *TaskFiles, old: *TaskFiles) !void {
        var fd_it = old.map.iterator(.{});
        while (fd_it.next()) |id| {
            if (id > self.map.capacity()) {
                self.map.resize(self.map.capacity() * 2, false) catch |err| {
                    kernel.logger.ERROR("TaskFiles.dup(): failed to resize map: {any}", .{err});
                    return errors.ENOMEM;
                };
            }
            self.map.set(id);
            errdefer self.map.unset(id);
            if (id > 2) { // standard IO don't exist yet
                if (old.fds.get(id)) |file| {
                    file.ref.ref();
                    try self.fds.put(id, file);
                } else {
                    kernel.logger.ERROR("TaskFiles.dup(): failed to get id {d} from fds", .{id});
                    return errors.ENOMEM;
                }
            }
        }
    }

    pub fn releaseFD(self: *TaskFiles, fd: u32) bool {
        self.unsetFD(fd);
        if (self.fds.get(fd)) |file| {
            _ = self.fds.remove(fd);
            file.ref.unref();
            return true;
        }
        return false;
    }

    pub fn getNextFD(self: *TaskFiles) anyerror!u32 {
        var it = self.map.iterator(.{
            .kind = .unset,
            .direction = .forward,
        });
        if (it.next()) |index| {
            self.map.set(index);
            return index;
        }
        const result = self.map.capacity(); // Look into if capacity is taken or not
        try self.map.resize(self.map.capacity() * 2 , false);
        return result;
    }

    pub fn unsetFD(self: *TaskFiles, fd: u32) void {
        if (fd < self.map.capacity()) {
            self.map.unset(fd);
        }
    }

    pub fn setFD(self: *TaskFiles, fd: u32, file: *File) !void {
        if (fd >= self.map.capacity()) {
            self.map.resize(fd + 1, false) catch |err| {
                kernel.logger.ERROR(
                    "TaskFiles.setFD(): failed to resize map: {t}",
                    .{err}
                );
                return errors.ENOMEM;
            };
        }
        self.map.set(fd);
        errdefer self.map.unset(fd);
        self.fds.put(fd, file) catch |err| {
            kernel.logger.ERROR(
                "TaskFiles.setFD(): failed to put fd {d} into fds: {t}",
                .{fd, err}
            );
            return errors.ENOMEM;
        };
    }
};

pub fn readdirVFS(base: *fs.File, buf: []u8) !u32 {
    if (base.path.dentry.tree.child) |ch| {
        var it = ch.siblingsIterator();
        var off: u32 = 0;
        var idx: u32 = 0;
        while (it.next()) |d| {
            if (idx < base.pos) {
                idx += 1;
                continue;
            }
            idx += 1;
            const _d = d.curr.entry(fs.DEntry, "tree");
            var dent = fs.LinuxDirent{
                .ino = _d.inode.i_no,
                .type = 0,
                .reclen = @intCast(@sizeOf(fs.LinuxDirent) + _d.name.len + 1),
                .off = off,
            };
            dent.setType(_d.inode.mode);
            if (dent.reclen % @sizeOf(usize) != 0) {
                dent.reclen += @sizeOf(usize) - (dent.reclen % @sizeOf(usize));
            }
            if (off + dent.reclen > buf.len) {
                base.pos = idx - 1;
                return off;
            }
            const name_offset = off + @sizeOf(fs.LinuxDirent);
            @memcpy(buf[off..name_offset], @as([*]u8, @ptrCast(&dent)));
            @memcpy(buf[name_offset..name_offset + _d.name.len], _d.name);
            buf[name_offset + _d.name.len] = 0;
            off += dent.reclen;
        }
        base.pos = idx;
        return off;
    }
    return 0;
}
