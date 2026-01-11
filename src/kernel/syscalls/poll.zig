const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

pub const POLLIN:  u16 = 0x0001;
pub const POLLOUT: u16 = 0x0004;

pub const PollFd = extern struct {
    fd: i32,
    events: u16,
    revents: u16,
};

pub fn poll(user_fds: ?[*]PollFd, nfds: u32, timeout_ms: i32) !u32 {
    if (user_fds == null and nfds != 0) {
        return errors.EINVAL;
    }
    krn.logger.DEBUG(
        "poll nfds {d}, timeout {d}ms",
        .{nfds, timeout_ms}
    );
    var fd_count: u32 = 0;
    for (0..nfds) |i| {
        krn.logger.DEBUG(
            "  - fd {d}, events {x}, revents {x}",
            .{
                    user_fds.?[i].fd,
                    user_fds.?[i].events,
                    user_fds.?[i].revents
                }
        );
        // Immediately report all fds as ready
        if (user_fds.?[i].events & POLLIN != 0)
            user_fds.?[i].revents |= POLLIN;
        if (user_fds.?[i].events & POLLOUT != 0)
            user_fds.?[i].revents |= POLLOUT;
        if (user_fds.?[i].revents != 0) {
            fd_count += 1;
        }
    }
    return fd_count;
}
