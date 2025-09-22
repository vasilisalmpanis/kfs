const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");

pub fn getdents(_: u32, _: [*]u8, _: u32) !u32 {
    return errors.EFAULT;
}

pub fn getdents64(fd: u32, dirents: [*]u8, size: u32) !u32 {
    if (krn.task.current.files.fds.get(fd)) |dir_file| {
        if (dir_file.inode.mode.isDir()) {
            if (dir_file.ops.readdir) |readdir| {
                if (krn.mm.kmallocSlice(u8, size)) |buf_slice| {
                    defer krn.mm.kfree(buf_slice.ptr);
                    krn.logger.INFO("about to read dir\n",.{});
                    const ret =  try readdir(dir_file, buf_slice);
                    krn.logger.INFO("Read from {x}-{x} \n{s}\n",.{@intFromPtr(dirents), @intFromPtr(dirents) + ret, buf_slice});
                    var offset: u32 = 0;
                    var u_off: u32 = 0;
                    var dirent: *krn.fs.LinuxDirent = @ptrCast(@alignCast(buf_slice.ptr));
                    const ent_size = @sizeOf(krn.fs.Dirent64) - 1;
                    while (offset < ret) {
                        var temp = krn.fs.Dirent64{
                            .ino = @intCast(dirent.ino),
                            .off = @intCast(dirent.off),
                            .reclen = dirent.reclen + (@sizeOf(krn.fs.Dirent64) - @sizeOf(krn.fs.LinuxDirent)), 
                            .type = dirent.type,
                        };
                        const name_start: u32 = u_off + ent_size;
                        @memcpy(dirents[u_off..name_start], @as([*]u8, @ptrCast(&temp))[0..ent_size]);
                        const entry_name: []u8 = dirent.getName();
                        @memcpy(dirents[name_start..name_start + entry_name.len], entry_name);
                        krn.logger.INFO("entry name {s} {s}\n", .{entry_name, dirents[name_start..name_start + entry_name.len]});
                        dirents[name_start + entry_name.len] = 0;
                        u_off += temp.reclen;
                        if (u_off > size)
                            break;
                        offset = offset + dirent.reclen;
                        dirent = @ptrCast(@alignCast(&buf_slice[offset]));
                    }
                    return u_off;
                }
            }
            return errors.ENOENT;
        }
        return errors.ENOTDIR;
    }
    return errors.EBADF;
}
