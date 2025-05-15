const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const sockets = @import("../net/socket.zig");

pub fn close(fd: u32) i32 {
    if (sockets.findById(fd)) |socket| {
        socket.delete();
    } else {
        return -errors.EBADF;
    }
    return 0;
}
