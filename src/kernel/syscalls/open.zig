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
    var target_path = parent_dir;
    target_path.stepInto(file_segment) catch {
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
            target_path = .{
                .dentry = new_dentry,
                .mnt = parent_dir.mnt,
            };
        } else {
            return errors.ENOENT;
        }
    };
    const new_file: *fs.File = fs.File.new(target_path) catch {
        target_path.dentry.tree.del();
        kernel.mm.kfree(target_path.dentry.inode);
        kernel.mm.kfree(target_path.dentry);
        return errors.ENOMEM;
    };
    new_file.mode = mode;
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
    return fd;
}
