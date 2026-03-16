const std = @import("std");
const krn = @import("../main.zig");
const fs = @import("../fs/fs.zig");
const errors = @import("error-codes.zig").PosixError;

pub fn chmod(path: ?[*:0]const u8, mode: fs.UMode) !u32 {
    if (path == null)
        return errors.EFAULT;
    const _path: []const u8 = std.mem.span(path.?);
    var _mode = mode;
    const resolved = try fs.path.resolve(_path);
    defer resolved.release();
    if (
        krn.task.current.uid != 0 and
        resolved.dentry.inode.uid != krn.task.current.uid
    )
        return errors.EPERM;
    if (
        krn.task.current.uid != 0 and
        !krn.task.current.inGroup(resolved.dentry.inode.gid)
    )
        _mode.unSetSGID();
    const mask: u7 = fs.S_ISGID | fs.S_ISUID | fs.S_ISVTX;
    _mode.type = (_mode.type & mask) | (resolved.dentry.inode.mode.type & ~mask);
    if (resolved.dentry.inode.ops.setattr) |_setattr| {
        const attr = fs.InodeAttrs{
            .mode = &_mode,
        };
        try _setattr(resolved.dentry.inode, &attr);
    }
    return 0;
}

pub fn fchmod(fd: u32, mode: fs.UMode) !u32 {
    if (krn.task.current.files.fds.get(fd)) |file| {
        file.ref.ref();
        defer file.ref.unref();
        var _mode = mode;
        if (
            krn.task.current.uid != 0 and
            file.inode.uid != krn.task.current.uid
        )
            return errors.EPERM;
        if (
            krn.task.current.uid != 0 and
            !krn.task.current.inGroup(file.inode.gid)
        )
            _mode.unSetSGID();
        const mask: u7 = fs.S_ISGID | fs.S_ISUID | fs.S_ISVTX;
        _mode.type = (_mode.type & mask) | (file.inode.mode.type & ~mask);
        if (file.inode.ops.setattr) |_setattr| {
            const attr = fs.InodeAttrs{
                .mode = &_mode,
            };
            try _setattr(file.inode, &attr);
            return 0;
        }
        return errors.EINVAL;
    }
    return errors.EBADF;
}
