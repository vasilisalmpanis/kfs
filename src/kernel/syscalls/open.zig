const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const kernel = @import("../main.zig");

pub fn open(
    filename: [*:0]u8,
    flags: u16,
    mode: fs.UMode,
) !u32 {
    var new: bool = false;
    const fd = tsk.current.files.getNextFD() catch {
        return errors.EMFILE;
    };
    const path = std.mem.span(filename);
    var file_segment: []const u8 = "";
    const parent_dir = fs.path.dir_resolve(path, &file_segment) catch {
        return errors.ENOENT;
    };
    const parent_inode: *fs.Inode = parent_dir.dentry.inode;
    const target_dentry: *fs.DEntry = parent_inode.ops.lookup(parent_inode, file_segment) catch res: {
        if (flags & fs.file.O_CREAT != 0) {
            const new_inode: *fs.Inode = parent_inode.ops.create(parent_inode, file_segment,mode) catch |err| {
                tsk.current.files.unsetFD(fd);
                switch (err) {
                    error.OutOfMemory => { return errors.ENOMEM; },
                    error.Access => { return errors.EACCES; },
                    else => { return errors.ENOENT; },
                }
            };
            const new_dentry: *fs.DEntry = fs.DEntry.alloc(file_segment, new_inode.sb, new_inode) catch {
                kernel.mm.kfree(new_inode);
                return errors.ENOMEM;
            };
            new = true;
            parent_dir.dentry.tree.addChild(&new_dentry.tree);
            fs.dcache.put(
                fs.DentryHash{
                    .ino = parent_inode.i_no,
                    .name = file_segment,
                },
                new_dentry
            ) catch {
                new_dentry.tree.del();
                kernel.mm.kfree(new_dentry);
                kernel.mm.kfree(new_inode);
                return errors.ENOMEM;
            };
            break :res new_dentry;
        } else {
            return errors.ENOENT;
        }
    };
    const new_file: *fs.File = target_dentry.inode.ops.newFile(target_dentry.inode) catch {
        target_dentry.tree.del();
        kernel.mm.kfree(target_dentry.inode);
        kernel.mm.kfree(target_dentry);
        return errors.ENOMEM;
    };
    new_file.mode = mode;
    new_file.flags = flags;
    new_file.ops.open(new_file, target_dentry.inode) catch {
        kernel.mm.kfree(new_file);
        target_dentry.tree.del();
        kernel.mm.kfree(target_dentry.inode);
        kernel.mm.kfree(target_dentry);
        return errors.ENOENT;
    };
    kernel.task.current.files.fds.put(fd, new_file) catch {
        // TODO: maybe call close?
        kernel.mm.kfree(new_file);
        target_dentry.tree.del();
        kernel.mm.kfree(target_dentry.inode);
        kernel.mm.kfree(target_dentry);
        return errors.ENOENT;
    };
    return fd;
}
