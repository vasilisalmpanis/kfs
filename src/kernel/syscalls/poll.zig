const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");
const std = @import("std");

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

pub const FD_SETSIZE:   usize = 1024;
pub const NFDBITS:      usize = @bitSizeOf(usize);
pub const FD_WORDS:     usize = FD_SETSIZE / NFDBITS;

const BitIdxType = @Type(
    std.builtin.Type{
        .int = .{
            .bits = @ctz(@as(usize, 1)),
            .signedness = .unsigned
        }
    }
);

pub const FDSet = extern struct {
    fds_bits: [FD_WORDS]usize,

    pub fn isSet(self: *const FDSet, fd: usize) bool {
        if (fd >= FD_SETSIZE)
            return false;
        const word_idx = fd / NFDBITS;
        const bit_idx: BitIdxType = @intCast(fd % NFDBITS);
        return (
            self.fds_bits[word_idx] & (@as(usize, 1) << bit_idx)
        ) != 0;
    }

    pub fn set(self: *FDSet, fd: usize) void {
        if (fd >= FD_SETSIZE)
            return;
        const word_idx = fd / NFDBITS;
        const bit_idx: BitIdxType = @intCast(fd % NFDBITS);
        self.fds_bits[word_idx] |= (@as(usize, 1) << bit_idx);
    }

    pub fn clr(self: *FDSet, fd: usize) void {
        if (fd >= FD_SETSIZE)
            return;
        const word_idx = fd / NFDBITS;
        const bit_idx: BitIdxType = @intCast(fd % NFDBITS);
        self.fds_bits[word_idx] &= ~(@as(usize, 1) << bit_idx);
    }

    pub fn zero(self: *FDSet) void {
        for (&self.fds_bits) |*word| {
            word.* = 0;
        }
    }
};

const PollRes = struct {
    read: bool,
    write: bool,
    except: bool,
};

fn pollOneFd(
    fd: usize,
    check_read: bool,
    check_write: bool,
    check_except: bool
) ?PollRes {
    const file = krn.task.current.files.fds.get(@intCast(fd))
        orelse return null;

    var events: u16 = 0;
    if (check_read)
        events |= POLLIN;
    if (check_write)
        events |= POLLOUT;
    if (check_except)
        events |= POLLPRI;

    var pollfd = PollFd{
        .fd = @intCast(fd),
        .events = events,
        .revents = 0,
    };

    if (file.ops.poll) |_poll| {
        _ = _poll(file, &pollfd) catch {};
    }

    const rd = check_read and (pollfd.revents & (POLLIN | POLLERR | POLLHUP)) != 0;
    const wr = check_write and (pollfd.revents & (POLLOUT | POLLERR | POLLHUP)) != 0;
    const ex = check_except and (pollfd.revents & POLLPRI) != 0;
    return PollRes{
        .read = rd,
        .write = wr,
        .except = ex,
    };
}

fn doPollFds(
    max_fd: usize,
    read_fds: ?*const FDSet,
    write_fds: ?*const FDSet,
    except_fds: ?*const FDSet,
    result_read: *FDSet,
    result_write: *FDSet,
    result_except: *FDSet,
) ?u32 {
    var ready_count: u32 = 0;

    result_read.zero();
    result_write.zero();
    result_except.zero();

    for (0..max_fd) |fd| {
        const check_read =
            if (read_fds) |rfd| rfd.isSet(fd)
            else false;
        const check_write =
            if (write_fds) |wfd| wfd.isSet(fd)
            else false;
        const check_except =
            if (except_fds) |efd| efd.isSet(fd)
            else false;
        if (!check_read and !check_write and !check_except) {
            continue;
        }

        const result = pollOneFd(
            fd,
            check_read,
            check_write,
            check_except
        ) orelse
            return null;

        if (result.read) {
            result_read.set(fd);
            ready_count += 1;
        }
        if (result.write) {
            result_write.set(fd);
            ready_count += 1;
        }
        if (result.except) {
            result_except.set(fd);
            ready_count += 1;
        }
    }
    return ready_count;
}

pub fn newselect(
    nfds: i32,
    read_fds: ?*FDSet,
    write_fds: ?*FDSet,
    except_fds: ?*FDSet,
    timeout: ?*krn.time.kernel_timespec,
    sigmask: ?*krn.signals.sigset_t,
) !u32 {
    _ = sigmask;

    if (nfds < 0) {
        return errors.EINVAL;
    }
    if (nfds > @as(i32, @intCast(FD_SETSIZE))) {
        return errors.EINVAL;
    }

    const max_fd: usize = @intCast(nfds);

    var timeout_ms: i32 = -1; // -1 means wait indefinitely
    if (timeout) |t| {
        if (!t.isValid()) {
            return errors.EINVAL;
        }
        const sec_ms: i64 = @as(i64, t.tv_sec) * 1000;
        const nsec_ms: i64 = @divTrunc(@as(i64, t.tv_nsec), 1000000);
        timeout_ms = @intCast(sec_ms + nsec_ms);
    }

    const start_time = krn.currentMs();

    var result_read: FDSet = .{ .fds_bits = .{0} ** FD_WORDS };
    var result_write: FDSet = .{ .fds_bits = .{0} ** FD_WORDS };
    var result_except: FDSet = .{ .fds_bits = .{0} ** FD_WORDS };

    while (true) {
        const ready_count = doPollFds(
            max_fd,
            read_fds,
            write_fds,
            except_fds,
            &result_read,
            &result_write,
            &result_except,
        ) orelse {
            return errors.EBADF;
        };

        if (ready_count > 0) {
            if (read_fds) |rfd|
                rfd.* = result_read;
            if (write_fds) |wfd|
                wfd.* = result_write;
            if (except_fds) |efd|
                efd.* = result_except;
            return ready_count;
        }

        if (timeout_ms == 0) {
            if (read_fds) |rfd|
                rfd.zero();
            if (write_fds) |wfd|
                wfd.zero();
            if (except_fds) |efd|
                efd.zero();
            return 0;
        }

        if (timeout_ms > 0) {
            const elapsed = krn.currentMs() - start_time;
            if (elapsed >= @as(u32, @intCast(timeout_ms))) {
                if (read_fds) |rfd|
                    rfd.zero();
                if (write_fds) |wfd|
                    wfd.zero();
                if (except_fds) |efd|
                    efd.zero();
                return 0;
            }
        }

        var wait_timeout: u32 = 0;
        const curr_time = krn.currentMs();
        if (timeout_ms < 0) {
            wait_timeout = 20; // Poll every 20ms
        } else {
            const elapsed = curr_time - start_time;
            const remaining = @as(u32, @intCast(timeout_ms)) -| elapsed;
            wait_timeout = remaining;
        }

        // TODO: implement normal waiting
        if (wait_timeout > 20)
            wait_timeout = 20;
        krn.task.current.wakeup_time = curr_time + wait_timeout;
        krn.task.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
    }
}
