const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const arch = @import("arch");
const sockets = @import("../net/socket.zig");
const kernel = @import("../main.zig");

pub fn close(fd: u32) !u32 {
    if (tsk.current.files.releaseFD(fd)) {
        kernel.logger.INFO("finished closing {d}\n", .{fd});
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
