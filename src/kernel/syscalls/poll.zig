const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

pub const POLLIN:  u16      = 0x0001;
pub const POLLPRI: u16      = 0x0002;
pub const POLLOUT: u16      = 0x0004;
pub const POLLERR: u16      = 0x0008;
pub const POLLHUP: u16      = 0x0010;
pub const POLLNVAL: u16     = 0x0020;

pub const PollFd = extern struct {
    fd: i32,
    events: u16,
    revents: u16,
};

pub fn poll(user_fds: ?[*]PollFd, nfds: u32, timeout_ms: i32) !u32 {
    if (user_fds == null and nfds != 0) {
        return errors.EINVAL;
    }
    const curr_time = krn.currentMs();
    var fd_count: u32 = 0;
    for (0..nfds) |i| {
        // krn.logger.INFO("poll {d}: {any}", .{});
        const fd: i32 = user_fds.?[i].fd;
        if (fd < 0) {
            user_fds.?[i].revents = 0;
            continue ;
        }
        if (krn.task.current.files.fds.get(@intCast(fd))) |file| {
            if (file.ops.poll) |_poll| {
                fd_count += try _poll(file, &user_fds.?[i]);
            } else {
                user_fds.?[i].revents |= POLLNVAL;
            }
        } else {
            user_fds.?[i].revents |= POLLNVAL;
            continue ;
        }
    }
    if (timeout_ms == 0) {
        return fd_count;
    }
    if (fd_count == 0) {
        if (timeout_ms < 0) {
            krn.task.current.wakeup_time = 1;
            fd_count = 1;
        } else {
            krn.task.current.wakeup_time = curr_time + @as(u32, @intCast(timeout_ms));
        }
        krn.task.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
    }
    return fd_count;
}
