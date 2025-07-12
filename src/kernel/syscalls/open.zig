const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const fs = @import("../fs/fs.zig");

pub fn open(
    filename: [*]u8,
    flags: i32,
    mode: fs.UMode,
) i32 {
    _ = mode;
    _ = flags;
    const fd = tsk.current.files.getNextFD() catch {
        return -errors.EMFILE;
    };
    _ = fd;
    _ = filename;
    return 0;
}
