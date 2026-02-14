const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");
const std = @import("std");
const krn = @import("../main.zig");
const mod = @import("modules");

pub fn init_module(image: [*]u8, size: u32, name: [*:0]u8) !u32 {
    const name_span: [:0]const u8 = std.mem.span(name);
    _ = try mod.load_module(image[0..size], name_span);
    return 0;
}

pub fn finit_module(fd: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        if (!file.mode.canRead(file.inode.uid, file.inode.gid)) {
            return errors.EACCES;
        }
        if (file.mode.isDir())
            return errors.EISDIR;
        if (file.path) |_path| {
            const size = file.inode.size;
            const elf = krn.mm.kmallocSlice(u8, size);
            if (elf) |_elf| {
                defer krn.mm.kfree(_elf.ptr);
                var offset: u32 = 0;
                while (offset < file.inode.size) {
                    const read = try file.ops.read(
                        file,
                        @ptrCast(@alignCast(&_elf[offset])),
                        file.inode.sb.?.block_size,
                    );
                    if (read == 0)
                        break;
                    offset += read;
                }
                _ = try mod.load_module(_elf, _path.dentry.name);
                return 0;
            }
            return errors.ENOMEM;
        }
        return errors.EBADF;
    }
    return errors.EBADF;
}

pub fn delete_module(name: ?[*:0]const u8) !u32 {
    if (name == null) {
        return errors.ENOENT;
    }
    const _name: [:0]const u8 = std.mem.span(name.?);
    if (_name.len == 0) {
        return errors.ENOENT;
    }
    try mod.removeModule(_name);
    return 0;
}
