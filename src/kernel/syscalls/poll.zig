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

const POLL_TABLE_INLINE_SIZE = 64;
const POLL_TABLE_ALLOC_SIZE = 1024;

const PollTableEntry = struct{
    node: krn.wq.WaitQueueNode,
    head: *krn.wq.WaitQueueHead,

    pub fn init(
        head: *krn.wq.WaitQueueHead,
    ) PollTableEntry {
        return PollTableEntry{
            .node = krn.wq.WaitQueueNode.init(krn.task.current),
            .head = head,
        };
    }
};

pub const PollTable = struct {
    wq_nodes_inline: [POLL_TABLE_INLINE_SIZE]?PollTableEntry = .{null} ** POLL_TABLE_INLINE_SIZE,
    wq_nodes_idx: usize = 0,
    wq_nodes: ?std.ArrayList(?PollTableEntry) = null,

    pub fn init() PollTable {
        return PollTable{};
    }

    /// Creartes WaitQueueNode, adds it to PollTable and to WaitQueue
    pub fn addNode(
        self: *PollTable,
        head: *krn.wq.WaitQueueHead
    ) !void {
        if (self.wq_nodes_idx < POLL_TABLE_INLINE_SIZE) {
            self.wq_nodes_inline[self.wq_nodes_idx] = PollTableEntry.init(head);
            const entry = &self.wq_nodes_inline[self.wq_nodes_idx];
            self.wq_nodes_idx += 1;
            entry.*.?.node.setup();
            entry.*.?.node.wake_fn = null;
            head.addToQueue(&entry.*.?.node);
            return ;
        }
        if (self.wq_nodes == null) {
            self.wq_nodes = try std.ArrayList(?PollTableEntry).initCapacity(
                krn.mm.kernel_allocator.allocator(),
                POLL_TABLE_ALLOC_SIZE
            );
        }
        try self.wq_nodes.?.append(
            krn.mm.kernel_allocator.allocator(),
            PollTableEntry.init(head)
        );
        const nodes = &self.wq_nodes.?;
        const entry = &nodes.items[nodes.items.len - 1];
        entry.*.?.node.setup();
        entry.*.?.node.wake_fn = null;
        head.addToQueue(&entry.*.?.node);
        return ;
    }

    pub fn deinit(self: *PollTable) void {
        for (self.wq_nodes_inline[0..self.wq_nodes_idx]) |*entry| {
            if (entry.*) |*ent| {
                ent.head.removeNode(&ent.node);
            }
            entry.* = null;
        }
        self.wq_nodes_idx = 0;

        if (self.wq_nodes) |*arr| {
            for (arr.items) |*entry| {
                if (entry.*) |*ent| {
                    ent.head.removeNode(&ent.node);
                }
                entry.* = null;
            }
            arr.deinit(krn.mm.kernel_allocator.allocator());
            self.wq_nodes = null;
        }
    }
};

pub fn poll(user_fds: ?[*]PollFd, nfds: u32, timeout_ms: i32) !u32 {
    if (user_fds == null and nfds != 0) {
        return errors.EINVAL;
    }
    if (nfds > POLL_TABLE_INLINE_SIZE + POLL_TABLE_ALLOC_SIZE)
        return errors.EINVAL;
    const start_time = krn.currentMs();
    if (nfds == 0) {
        if (timeout_ms == 0)
            return 0;
        if (timeout_ms < 0) {
            krn.task.current.wakeup_time = 0;
        } else {
            krn.task.current.wakeup_time = start_time + @as(u32, @intCast(timeout_ms));
        }
        krn.task.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
        if (krn.task.current.sighand.hasPending())
            return errors.EINTR;
        return 0;
    }
    var poll_table = PollTable.init();
    defer poll_table.deinit();
    var pt_added = false;
    var fd_count: u32 = 0;
    while (fd_count == 0) {
        for (0..nfds) |i| {
            // krn.logger.INFO("poll {d}: {any}", .{});
            const fd: i32 = user_fds.?[i].fd;
            if (fd < 0) {
                user_fds.?[i].revents = 0;
                continue ;
            }
            if (krn.task.current.files.fds.get(@intCast(fd))) |file| {
                file.ref.ref();
                defer file.ref.unref();
                if (file.ops.poll) |_poll| {
                    fd_count += try _poll(
                        file,
                        &user_fds.?[i],
                        if (pt_added) null else &poll_table
                    );
                } else {
                    user_fds.?[i].revents |= POLLNVAL;
                }
            } else {
                user_fds.?[i].revents |= POLLNVAL;
                continue ;
            }
        }
        pt_added = true;
        if (timeout_ms == 0) {
            break ;
        }
        if (fd_count == 0) {
            if (timeout_ms < 0) {
                krn.task.current.wakeup_time = 0;
            } else {
                const curr_time = krn.currentMs();
                const to_sleep = @as(u32, @intCast(timeout_ms)) -| (curr_time - start_time);
                if (to_sleep == 0)
                    break ;
                krn.task.current.wakeup_time = curr_time + @as(u32, @intCast(to_sleep));
            }
            krn.task.current.state = .INTERRUPTIBLE_SLEEP;
            krn.sched.reschedule();

            if (krn.task.current.sighand.hasPending())
                return errors.EINTR;
        }
    }
    return fd_count;
}

pub const FD_SETSIZE:   usize = 1024;
pub const NFDBITS:      usize = @bitSizeOf(usize);
pub const FD_WORDS:     usize = FD_SETSIZE / NFDBITS;

const BitIdxType = @Type(
    std.builtin.Type{
        .int = .{
            .bits = if (@sizeOf(usize) == @sizeOf(u32)) 5 else 6,
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
    check_except: bool,
    poll_table: ?*PollTable,
) ?PollRes {
    const file = krn.task.current.files.fds.get(@intCast(fd))
        orelse return null;
    file.ref.ref();
    defer file.ref.unref();
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
        _ = _poll(file, &pollfd, poll_table) catch {};
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
    poll_table: ?*PollTable,
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
            check_except,
            poll_table,
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

fn doSelect(
    nfds: i32,
    read_fds: ?*FDSet,
    write_fds: ?*FDSet,
    except_fds: ?*FDSet,
    timeout_ms: i32,
) !u32 {
    if (nfds < 0) {
        return errors.EINVAL;
    }
    if (nfds > @as(i32, @intCast(FD_SETSIZE))) {
        return errors.EINVAL;
    }

    const max_fd: usize = @intCast(nfds);

    const start_time = krn.currentMs();

    var result_read: FDSet = .{ .fds_bits = .{0} ** FD_WORDS };
    var result_write: FDSet = .{ .fds_bits = .{0} ** FD_WORDS };
    var result_except: FDSet = .{ .fds_bits = .{0} ** FD_WORDS };

    var poll_table = PollTable.init();
    defer poll_table.deinit();
    var pt_added = false;
    while (true) {
        const ready_count = doPollFds(
            max_fd,
            read_fds,
            write_fds,
            except_fds,
            &result_read,
            &result_write,
            &result_except,
            if (pt_added) null else &poll_table,
        ) orelse {
            return errors.EBADF;
        };
        pt_added = true;

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
            krn.task.current.wakeup_time = 0;
        } else {
            const elapsed = curr_time - start_time;
            const remaining = @as(u32, @intCast(timeout_ms)) -| elapsed;
            wait_timeout = remaining;
            krn.task.current.wakeup_time = curr_time + wait_timeout;
        }
        krn.task.current.state = .INTERRUPTIBLE_SLEEP;
        krn.sched.reschedule();
    }
}

pub fn newselect(
    nfds: i32,
    read_fds: ?*FDSet,
    write_fds: ?*FDSet,
    except_fds: ?*FDSet,
    timeout: ?*krn.kernel_timespec,
    _: u32,
) !u32 {
    if (nfds > POLL_TABLE_INLINE_SIZE + POLL_TABLE_ALLOC_SIZE)
        return errors.EINVAL;
    var timeout_ms: i32 = -1;
    if (timeout) |t| {
        if (!t.isValid()) {
            return errors.EINVAL;
        }
        const sec_ms: i64 = @as(i64, t.tv_sec) * 1000;
        const nsec_ms: i64 = @divTrunc(@as(i64, t.tv_nsec), 1_000_000);
        timeout_ms = @intCast(sec_ms + nsec_ms);
    }
    return doSelect(
        nfds,
        read_fds,
        write_fds,
        except_fds,
        timeout_ms,
    );
}
