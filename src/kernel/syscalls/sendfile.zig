const krn = @import("../main.zig");
const errors = @import("error-codes.zig").PosixError;

pub fn sendfile(out_fd: i32, in_fd: i32, offset: ?*u32, count: u32) !u32 {
    var u64_offset: ?*u64 = null;
    if (offset) |off| {
        u64_offset = @ptrCast(off);
    }

    const result = try sendfile64(out_fd, in_fd, u64_offset, count);

    if (offset) |off| {
        off.* = @intCast(u64_offset.?.*);
    }

    return result;
}

pub fn sendfile64(out_fd: i32, in_fd: i32, offset: ?*u64, count: u32) !u32 {
    if (in_fd < 0 or out_fd < 0) {
        return errors.EBADF;
    }

    const in_file = krn.task.current.files.fds.get(@intCast(in_fd)) orelse {
        return errors.EBADF;
    };

    const out_file = krn.task.current.files.fds.get(@intCast(out_fd)) orelse {
        return errors.EBADF;
    };

    if (!in_file.mode.canRead(krn.task.current.uid, krn.task.current.gid)) {
        return errors.EACCES;
    }
    if (!out_file.mode.canRead(krn.task.current.uid, krn.task.current.gid)) {
        return errors.EACCES;
    }

    if (in_file.inode.mode.isDir() or out_file.mode.isDir()) {
        return errors.EISDIR;
    }

    if (count == 0) {
        return 0;
    }

    const optimal_buffer_size = @min(count, out_file.inode.sb.?.block_size);
    const buffer_size = @max(optimal_buffer_size, 4096);

    const buffer = krn.mm.kmallocSlice(u8, buffer_size) orelse {
        return errors.ENOMEM;
    };
    defer krn.mm.kfree(buffer.ptr);

    var total_written: u32 = 0;
    var current_offset: u64 = 0;

    if (offset) |off| {
        current_offset = off.*;
    }

    const original_in_pos = in_file.pos;
    const original_out_pos = out_file.pos;
    if (offset != null) {
        defer {
            in_file.pos = original_in_pos;
            out_file.pos = original_out_pos;
        }
    }

    if (current_offset == 0 and in_file.pos >= in_file.inode.size) {
        return 0;
    }

    if (current_offset >= in_file.inode.size)
        return krn.errors.PosixError.EINVAL;

    in_file.pos = @intCast(current_offset);

    while (total_written < count) {
        const remaining = count - total_written;
        const to_read = @min(buffer.len, remaining);

        const bytes_read = try in_file.ops.read(in_file, buffer.ptr, to_read);
        if (bytes_read == 0) {
            break;
        }

        const bytes_written = try out_file.ops.write(out_file, buffer.ptr, bytes_read);
        if (bytes_written == 0) {
            break;
        }

        total_written += bytes_written;
        current_offset += bytes_written;
    }

    if (offset) |off| {
        off.* = current_offset;
    }

    return total_written;
}
