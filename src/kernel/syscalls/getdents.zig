const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");

pub fn getdents(_: u32, _: [*]u8, _: u32) !u32 {
    return errors.EFAULT;
}

pub fn getdents64(fd: u32, dirents: [*]u8, size: u32) !u32 {
    krn.logger.INFO("called with {d}\n", .{fd});
    if (krn.task.current.files.fds.get(fd)) |dir_file| {
        if (dir_file.inode.mode.isDir()) {
            if (dir_file.ops.readdir) |readdir| {
                if (krn.mm.kmallocSlice(u8, size)) |buf_slice| {
                    defer krn.mm.kfree(buf_slice.ptr);
                    const ret =  try readdir(dir_file, buf_slice);
                    var offset: u32 = 0;
                    var u_off: u32 = 0;
                    
                    // @sizeOf() returns 20 but name starts at offset 19
                    const header_size: u32 = @sizeOf(krn.fs.Dirent64) - 1;                    
                    while (offset < ret) {
                        const dirent: *krn.fs.LinuxDirent = @ptrCast(
                            @alignCast(&buf_slice[offset])
                        );
                        const entry_name: []u8 = dirent.getName();                        
                        var entry_size: u32 = header_size + @as(
                            u32, @intCast(entry_name.len)
                        ) + 1;
                        entry_size = (entry_size + 7) & ~@as(u32, 7);                        
                        if (u_off + entry_size > size) {
                            break;
                        }
                        var temp = krn.fs.Dirent64{
                            .ino = @intCast(dirent.ino),
                            .off = @intCast(dirent.off),
                            .reclen = @intCast(entry_size),
                            .type = dirent.type,
                        };
                        
                        @memcpy(
                            dirents[u_off..u_off + header_size],
                            @as([*]u8, @ptrCast(&temp))[0..header_size]
                        );                        
                        const name_start: u32 = u_off + header_size;
                        @memcpy(
                            dirents[name_start..name_start + @as(u32, @intCast(entry_name.len))],
                            entry_name
                        );
                        dirents[name_start + @as(u32, @intCast(entry_name.len))] = 0;
                        
                        u_off += entry_size;
                        offset += dirent.reclen;
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
