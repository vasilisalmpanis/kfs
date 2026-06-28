const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;

const EPOLL_CTL_ADD: i32 = 1;
const EPOLL_CTL_DEL: i32 = 2;
const EPOLL_CTL_MOD: i32 = 3;

const EPOLLIN: u32 = 0x001;
const EPOLLPRI: u32 = 0x002;
const EPOLLOUT: u32 = 0x004;
const EPOLLERR: u32 = 0x008;
const EPOLLHUP: u32 = 0x010;

const EPOLLONESHOT: u32 = 1 << 30;
const EPOLLET: u32 = 1 << 31;

pub const EpollEvent = extern struct {
    events: u32,
    data: u64,
};


fn getState(epfd: i32) !*krn.fs.epoll.EpollState {
    if (epfd < 0)
        return errors.EBADF;

    const file = krn.task.current.files.fds.get(@intCast(epfd)) orelse
        return errors.EBADF;
    if (file.ops != &krn.fs.epoll.ops)
        return errors.EINVAL;
    return @ptrCast(@alignCast(file.data));
}

fn findEntry(entries: []krn.fs.epoll.EpollEntry, fd: i32) ?usize {
    for (entries, 0..) |entry, idx| {
        if (entry.fd == fd)
            return idx;
    }
    return null;
}

fn epollToPoll(events: u32) u16 {
    var out: u16 = 0;
    if (events & EPOLLIN != 0)
        out |= krn.poll.POLLIN;
    if (events & EPOLLPRI != 0)
        out |= krn.poll.POLLPRI;
    if (events & EPOLLOUT != 0)
        out |= krn.poll.POLLOUT;
    return out;
}

fn pollToEpoll(events: u16) u32 {
    var out: u32 = 0;
    if (events & krn.poll.POLLIN != 0)
        out |= EPOLLIN;
    if (events & krn.poll.POLLPRI != 0)
        out |= EPOLLPRI;
    if (events & krn.poll.POLLOUT != 0)
        out |= EPOLLOUT;
    if (events & krn.poll.POLLERR != 0)
        out |= EPOLLERR;
    if (events & krn.poll.POLLHUP != 0)
        out |= EPOLLHUP;
    return out;
}

fn releaseEpollState(rc: *krn.RefCount) void {
    const inode: *krn.fs.Inode = @fieldParentPtr("ref", rc);
    krn.mm.kfree(inode);
}

pub fn epoll_create1(flags: u32) !u32 {
    const cloexec: u32 = krn.fs.file.O_CLOEXEC;
    if (flags & ~cloexec != 0)
        return errors.EINVAL;

    const state = krn.mm.kmalloc(krn.fs.epoll.EpollState) orelse
        return errors.ENOMEM;
    errdefer krn.mm.kfree(state);
    try state.init();
    errdefer state.deinit();

    const inode = try krn.fs.Inode.allocEmpty();
    errdefer krn.mm.kfree(inode);
    inode.fops = &krn.fs.epoll.ops;
    inode.mode = krn.fs.UMode.regular();

    const file = try krn.fs.File.pseudo(inode);
    errdefer file.ref.put();

    inode.ref.put(); // pseudo referenced inode
    file.mode = krn.fs.UMode.regular();
    file.flags |= krn.fs.file.O_RDWR;
    file.data = state;

    const fd = try krn.task.current.files.getNextFD();
    errdefer _ = krn.task.current.files.releaseFD(fd);

    try krn.task.current.files.setFD(fd, file);
    if (flags & cloexec != 0)
        krn.task.current.files.closexec.set(fd);
    return @intCast(fd);
}

pub fn epoll_create(size: i32) !u32 {
    if (size <= 0)
        return errors.EINVAL;
    return try epoll_create1(0);
}

pub fn epoll_ctl(epfd: i32, op: i32, fd: i32, event: ?*const EpollEvent) !u32 {
    if (fd == epfd)
        return errors.EINVAL;
    if (fd < 0)
        return errors.EBADF;

    const state = try getState(epfd);

    switch (op) {
        EPOLL_CTL_ADD => {
            const ev = event orelse
                return errors.EFAULT;
            if (ev.events & (EPOLLONESHOT | EPOLLET) != 0)
                return errors.ENOSYS;
            const file = krn.task.current.files.fds.get(@intCast(fd)) orelse
                return errors.EBADF;
            if (file.inode.fops == &krn.fs.epoll.ops)
                return errors.ELOOP;
            if (findEntry(state.entries.items, fd) != null)
                return errors.EEXIST;
            try state.entries.append(krn.mm.kernel_allocator.allocator(), .{
                .fd = fd,
                .events = ev.events,
                .data = ev.data,
            });
            krn.logger.DEBUG(
                "[epoll_ctl ADD] pid={d} epfd={d} fd={d} events=0x{x}",
                .{ krn.task.current.pid, epfd, fd, ev.events },
            );
        },
        EPOLL_CTL_DEL => {
            const idx = findEntry(state.entries.items, fd) orelse
                return errors.ENOENT;
            const last = state.entries.items.len - 1;
            state.entries.items[idx] = state.entries.items[last];
            state.entries.items.len = last;
        },
        EPOLL_CTL_MOD => {
            const ev = event orelse
                return errors.EFAULT;
            if (ev.events & (EPOLLONESHOT | EPOLLET) != 0)
                return errors.ENOSYS;
            const idx = findEntry(state.entries.items, fd) orelse
                return errors.ENOENT;
            state.entries.items[idx].events = ev.events;
            state.entries.items[idx].data = ev.data;
            krn.logger.DEBUG(
                "[epoll_ctl MOD] pid={d} epfd={d} fd={d} events=0x{x}",
                .{ krn.task.current.pid, epfd, fd, ev.events },
            );
        },
        else => return errors.EINVAL,
    }

    return 0;
}

pub fn epoll_wait(epfd: i32, events: ?[*]EpollEvent, maxevents: i32, timeout_ms: i32) !u32 {
    const out_events = events orelse return errors.EFAULT;
    if (maxevents <= 0)
        return errors.EINVAL;
    if (timeout_ms < -1)
        return errors.EINVAL;

    const state = try getState(epfd);
    const start_time = krn.currentMs();
    var poll_table = krn.poll.PollTable.init();
    defer poll_table.deinit();
    var poll_table_added = false;
    var iter: u32 = 0;

    while (true) {
        iter += 1;
        var ready_count: u32 = 0;

        for (state.entries.items) |entry| {
            if (ready_count >= @as(u32, @intCast(maxevents)))
                break;

            var ready_events: u32 = 0;
            if (entry.fd >= 0) {
                if (krn.task.current.files.fds.get(@intCast(entry.fd))) |file| {
                    file.ref.get();
                    defer file.ref.put();

                    var pollfd = krn.poll.PollFd{
                        .fd = entry.fd,
                        .events = epollToPoll(entry.events),
                        .revents = 0,
                    };

                    if (file.ops.poll) |_poll| {
                        _ = try _poll(file, &pollfd, if (poll_table_added) null else &poll_table);
                    } else {
                        pollfd.revents |= krn.poll.POLLNVAL;
                    }
                    ready_events = pollToEpoll(pollfd.revents);
                } else {
                    ready_events = EPOLLERR | EPOLLHUP;
                }
            }

            if (ready_events != 0) {
                out_events[ready_count] = .{
                    .events = ready_events,
                    .data = entry.data,
                };
                ready_count += 1;
            }
        }

        if (ready_count > 0) {
            return ready_count;
        }
        if (timeout_ms == 0) {
            return 0;
        }

        poll_table_added = true;
        if (timeout_ms < 0) {
            krn.task.current.wakeup_time = 0;
        } else {
            const curr_time = krn.currentMs();
            const elapsed = curr_time - start_time;
            const to_sleep = @as(u32, @intCast(timeout_ms)) -| elapsed;
            if (to_sleep == 0) {
                return 0;
            }
            krn.task.current.wakeup_time = curr_time + to_sleep;
        }

        krn.task.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
        if (krn.task.current.hasPendingSignal()) {
            return errors.EINTR;
        }
    }
}

pub fn epoll_pwait(epfd: i32, events: ?[*]EpollEvent, maxevents: i32, timeout_ms: i32, sigmask: u32, sigsetsize: u32) !u32 {
    _ = sigmask;
    _ = sigsetsize;
    return try epoll_wait(epfd, events, maxevents, timeout_ms);
}

pub fn epoll_pwait2(
    epfd: i32, events: [*]EpollEvent, n: i32, timeout: krn.time.kernel_timespec,
    sigmask: ?*krn.signals.sigset_t,
) !u32 {
    krn.logger.DEBUG(
        "epoll_wait epfd: {d}, events: {any}, n: {d}, timeout: {any} sigmask: {any}",
        .{epfd, events, n, timeout, sigmask}
    );
    return try epoll_wait(epfd, events, n, @intCast(timeout.toMSec()));
}
