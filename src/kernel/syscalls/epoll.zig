const std = @import("std");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

const EPOLL_CLOEXEC = krn.fs.file.O_CLOEXEC;

const EPOLL_CTL_ADD = 1;
const EPOLL_CTL_DEL = 2;
const EPOLL_CTL_MOD = 3;

// Epoll event masks
const EPOLLIN       : u32 = 0x00000001;
const EPOLLPRI      : u32 = 0x00000002;
const EPOLLOUT      : u32 = 0x00000004;
const EPOLLERR      : u32 = 0x00000008;
const EPOLLHUP      : u32 = 0x00000010;
const EPOLLNVAL     : u32 = 0x00000020;
const EPOLLRDNORM   : u32 = 0x00000040;
const EPOLLRDBAND   : u32 = 0x00000080;
const EPOLLWRNORM   : u32 = 0x00000100;
const EPOLLWRBAND   : u32 = 0x00000200;
const EPOLLMSG      : u32 = 0x00000400;
const EPOLLRDHUP    : u32 = 0x00002000;

const EpollEvent = struct {
    events: u32,
    data:   u64,
};

fn doEpollCreate(flags: u32) !u32 {
    _ = flags;
    return errors.ENOSYS;
}

pub fn epoll_create(size: i32) !u32 {
    krn.logger.DEBUG("epoll_create {d}", .{size});
    if (size < 0)
        return errors.EINVAL;
    return try doEpollCreate(0);
}

pub fn epoll_create1(flags: u32) !u32 {
    krn.logger.DEBUG("epoll_create1 {x}", .{flags});
    return try doEpollCreate(flags);
}

pub fn epoll_ctl(epfd: i32, op: i32, fd: i32, epoll_event: ?*EpollEvent) !u32 {
    krn.logger.DEBUG(
        "epoll_ctl epfd: {d} op: {x} fd: {d} event: {any}",
        .{epfd, op, fd, epoll_event}
    );
    return errors.ENOSYS;
}

pub fn epoll_wait(epfd: i32, events: [*]EpollEvent, n: i32, timeout: i32) !u32 {
    krn.logger.DEBUG(
        "epoll_wait epfd: {d}, events: {any}, n: {d}, timeout: {d}",
        .{epfd, events, n, timeout}
    );
    return errors.ENOSYS;
}

pub fn epoll_pwait(
    epfd: i32, events: [*]EpollEvent, n: i32, timeout: i32,
    sigmask: ?*krn.signals.sigset_t,
) !u32 {
    krn.logger.DEBUG(
        "epoll_wait epfd: {d}, events: {any}, n: {d}, timeout: {d} sigmask: {any}",
        .{epfd, events, n, timeout, sigmask}
    );
    return errors.ENOSYS;
}

pub fn epoll_pwait2(
    epfd: i32, events: [*]EpollEvent, n: i32, timeout: krn.time.kernel_timespec,
    sigmask: ?*krn.signals.sigset_t,
) !u32 {
    krn.logger.DEBUG(
        "epoll_wait epfd: {d}, events: {any}, n: {d}, timeout: {any} sigmask: {any}",
        .{epfd, events, n, timeout, sigmask}
    );
    return errors.ENOSYS;
}
