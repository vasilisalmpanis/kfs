const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");

pub fn close(fd: u32) !u32 {
    if (tsk.current.files.releaseFD(fd)) {
        return 0;
    }
    return errors.EBADF;
    // if (sockets.findById(fd)) |socket| {
    //     socket.delete();
    // } else {
    //     return errors.EBADF;
    // }
}
