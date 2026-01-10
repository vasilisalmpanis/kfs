const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const kernel = @import("../main.zig");

pub fn close(fd: i32) !u32 {
    if (fd < 0)
        return errors.EBADF;
    if (tsk.current.files.releaseFD(@intCast(fd))) {
        kernel.logger.INFO("[PID {d}] finished closing {d}\n", .{tsk.current.pid, fd});
        return 0;
    }
    kernel.logger.INFO("error closing {d}\n", .{fd});
    return errors.EBADF;
    // if (sockets.findById(fd)) |socket| {
    //     socket.delete();
    // } else {
    //     return errors.EBADF;
    // }
}
