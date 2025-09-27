const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

pub fn do_open(
    parent_dir: fs.path.Path,
    name: []const u8,
    flags: u16,
    mode: fs.UMode
) !u32 {
    var new: bool = false;
    const fd = tsk.current.files.getNextFD() catch {
        return errors.EMFILE;
    };
    var new_mode = mode;
    errdefer _ = tsk.current.files.releaseFD(fd);
    const parent_inode: *fs.Inode = parent_dir.dentry.inode;
    var target_path = parent_dir.clone();
    target_path.stepInto(name) catch {
        if (flags & fs.file.O_CREAT != 0) {
            new_mode.type = kernel.fs.S_IFREG;
            const new_dentry = parent_inode.ops.create(
                parent_inode,
                name,
                new_mode,
                parent_dir.dentry
            ) catch |err| {
                tsk.current.files.unsetFD(fd);
                switch (err) {
                    error.OutOfMemory => { return errors.ENOMEM; },
                    error.Access => { return errors.EACCES; },
                    else => { return errors.ENOENT; },
                }
            };
            new = true;
            target_path.release();
            target_path = .{
                .dentry = new_dentry,
                .mnt = parent_dir.mnt,
            };
        } else {
            return errors.ENOENT;
        }
    };
    if (!target_path.dentry.inode.canAccess(flags)) {
        return errors.EACCES;
    }
    const new_file: *fs.File = fs.File.new(target_path) catch {
        target_path.dentry.tree.del();
        kernel.mm.kfree(target_path.dentry.inode);
        kernel.mm.kfree(target_path.dentry);
        return errors.ENOMEM;
    };
    new_file.mode = new_mode;
    new_file.flags = flags;
    new_file.ops.open(new_file, new_file.inode) catch {
        kernel.mm.kfree(new_file);
        target_path.dentry.tree.del();
        kernel.mm.kfree(target_path.dentry.inode);
        kernel.mm.kfree(target_path.dentry);
        return errors.ENOENT;
    };
    kernel.task.current.files.fds.put(fd, new_file) catch {
        // TODO: maybe call close?
        kernel.mm.kfree(new_file);
        target_path.dentry.tree.del();
        kernel.mm.kfree(target_path.dentry.inode);
        kernel.mm.kfree(target_path.dentry);
        return errors.ENOENT;
    };
    kernel.logger.DEBUG("opened {s} with fd {d}", .{name, fd});
    return fd;
}

pub fn open(
    filename: ?[*:0]u8,
    flags: u16,
    mode: fs.UMode,
) !u32 {
    if (filename) |f| {
        const path: []u8 = std.mem.span(f);
        kernel.logger.INFO("opening {s}\n", .{path});
        var file_segment: []const u8 = "";
        const parent_dir = try fs.path.dir_resolve(
            path,
            &file_segment
        );
        defer parent_dir.release();
        return try do_open(
            parent_dir,
            file_segment,
            flags,
            mode
        );
    }
    return errors.EFAULT;
}

pub fn openat(
    dirfd: u32,
    path: ?[*:0]const u8,
    flags: u16,
    mode: fs.UMode,
) !u32 {
    if (path == null) {
        return errors.EFAULT;
    }
    if (kernel.task.current.files.fds.get(dirfd)) |dir| {
        if (dir.path == null)
            return errors.EBADF;
        const path_sl: []const u8 = std.mem.span(path.?);
        var file_segment: []const u8 = "";
        const parent_dir = try fs.path.dir_resolve_from(
            path_sl,
            dir.path.?,
            &file_segment
        );
        defer parent_dir.release();
        return try do_open(
            parent_dir,
            file_segment,
            flags,
            mode
        );
    } else {
        return errors.EBADF;
    }
}
