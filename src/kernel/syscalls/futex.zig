const krn = @import("../main.zig");
const errors = @import("error-codes.zig").PosixError;
const lst = @import("../utils/list.zig");
const std = @import("std");

const FLAGS_SHARED: u32   = 0x0010;
const FLAGS_CLOCKRT: u32  = 0x0020;

pub const FUTEX_BITSET_MATCH_ANY: u32 = 0xffffffff;

pub const FUTEX_WAIT: u32            = 0;
pub const FUTEX_WAKE: u32            = 1;
pub const FUTEX_FD: u32              = 2;
pub const FUTEX_REQUEUE: u32         = 3;
pub const FUTEX_CMP_REQUEUE: u32     = 4;
pub const FUTEX_WAKE_OP: u32         = 5;
pub const FUTEX_LOCK_PI: u32         = 6;
pub const FUTEX_UNLOCK_PI: u32       = 7;
pub const FUTEX_TRYLOCK_PI: u32      = 8;
pub const FUTEX_WAIT_BITSET: u32     = 9;
pub const FUTEX_WAKE_BITSET: u32     = 10;
pub const FUTEX_WAIT_REQUEUE_PI: u32 = 11;
pub const FUTEX_CMP_REQUEUE_PI: u32  = 12;
pub const FUTEX_LOCK_PI2: u32        = 13;

pub const FUTEX_PRIVATE_FLAG: u32    = 128;
pub const FUTEX_CLOCK_REALTIME: u32  = 256;

const FUTEX_CMD_MASK: u32 = ~(FUTEX_PRIVATE_FLAG | FUTEX_CLOCK_REALTIME);

var futexes: ?std.AutoHashMap(FutexKey, *FutexQueue) = null;
var futexes_lock = krn.Spinlock.init();

const FutexKey = struct {
    addr:   usize,
    vas:    usize,
    // TODO: a real shared key should be unique for SHM segment
    // mapped at different VAs in different processes. Now we only key
    // by (vas, uaddr): cross-process shared futex isn't supported.

    fn init(uaddr: *u32, flags: u32) FutexKey {
        var _vas: usize = 0;
        if (flags & FLAGS_SHARED == 0 and krn.task.current.mm != null)
            _vas = krn.task.current.mm.?.vas;
        return .{
            .addr = @intFromPtr(uaddr),
            .vas = _vas,
        };
    }
};

const FutexQueue = struct {
    key:        FutexKey,
    waiters:    lst.ListHead,
    lock:       krn.Spinlock,

    fn setup(self: *FutexQueue, key: FutexKey) void {
        self.key = key;
        self.lock = krn.Spinlock.init();
        self.waiters.setup();
    }
};

const FutexWaiter = struct {
    lst:    lst.ListHead,
    task:   *krn.task.Task,
    bitset: u32,
    queue:  *FutexQueue,
    woken:  bool,
};

fn getQueue(key: FutexKey) ?*FutexQueue {
    const state = futexes_lock.lock_irq_disable();
    defer futexes_lock.unlock_irq_enable(state);

    if (futexes) |*map|
        return map.get(key);
    return null;
}

fn getOrCreateQueue(key: FutexKey) !*FutexQueue {
    {
        const state = futexes_lock.lock_irq_disable();
        defer futexes_lock.unlock_irq_enable(state);

        if (futexes == null) {
            futexes = std.AutoHashMap(FutexKey, *FutexQueue).init(
                krn.mm.kernel_allocator.allocator(),
            );
        }
        if (futexes.?.get(key)) |q|
            return q;
    }

    const queue = krn.mm.kmalloc(FutexQueue) orelse
        return errors.ENOMEM;
    queue.setup(key);

    const state = futexes_lock.lock_irq_disable();
    defer futexes_lock.unlock_irq_enable(state);

    if (futexes.?.get(key)) |_q| {
        krn.mm.kfree(queue);
        return _q;
    }
    futexes.?.put(key, queue) catch {
        krn.mm.kfree(queue);
        return errors.ENOMEM;
    };
    return queue;
}

fn timeoutMs(utime: ?*krn.time.kernel_timespec) !u32 {
    const ts = utime orelse
        return 0;
    if (!ts.isValid())
        return errors.EINVAL;
    const sec: u64 = @intCast(ts.tv_sec);
    const nsec: u64 = @intCast(ts.tv_nsec);
    const ms64: u64 = sec * 1000 + nsec / 1_000_000;
    if (ms64 > 0xFFFFFFFF)
        return errors.EINVAL;
    return @intCast(ms64);
}

fn cleanupAfterSleep(waiter: *FutexWaiter) bool {
    while (true) {
        const queue = waiter.queue;
        const lock_state = queue.lock.lock_irq_disable();
        if (queue != waiter.queue) {
            queue.lock.unlock_irq_enable(lock_state);
            continue;
        }
        const woken = waiter.woken;
        if (!woken) {
            waiter.lst.del();
            waiter.lst.setup();
        }
        queue.lock.unlock_irq_enable(lock_state);
        return woken;
    }
}

fn futexWait(
    uaddr: ?*u32,
    flags: u32,
    val: u32,
    utime: ?*krn.time.kernel_timespec,
    bitset: u32,
) !u32 {
    const user_addr = uaddr orelse
        return errors.EFAULT;

    const has_timeout = utime != null;
    const timeout = try timeoutMs(utime);
    if (has_timeout and timeout == 0) {
        if (user_addr.* != val)
            return errors.EAGAIN;
        return errors.ETIMEDOUT;
    }
    const deadline: u32 = if (has_timeout) krn.currentMs() +| timeout else 0;

    const key = FutexKey.init(user_addr, flags);
    const queue = try getOrCreateQueue(key);

    var waiter = FutexWaiter{
        .lst = lst.ListHead.init(),
        .task = krn.task.current,
        .bitset = bitset,
        .queue = queue,
        .woken = false,
    };
    waiter.lst.setup();

    const lock_state = queue.lock.lock_irq_disable();
    if (user_addr.* != val) {
        queue.lock.unlock_irq_enable(lock_state);
        return errors.EAGAIN;
    }
    queue.waiters.addTail(&waiter.lst);
    krn.task.current.wakeup_time = deadline;
    krn.task.current.state = .INTERRUPTIBLE_SLEEP;
    queue.lock.unlock_irq_enable(lock_state);

    krn.sched.reschedule();

    const woke = cleanupAfterSleep(&waiter);

    if (woke)
        return 0;
    if (krn.task.current.hasPendingSignal())
        // An untimed FUTEX_WAIT is restartable. A timed wait would need
        // restart_syscall to resume with the remaining timeout (a plain eip
        // rewind would wait the full duration again), so keep it on EINTR.
        return if (has_timeout) errors.EINTR else errors.ERESTARTSYS;
    if (has_timeout)
        return errors.ETIMEDOUT;
    return errors.EAGAIN;
}

fn wakeWaiter(waiter: *FutexWaiter) void {
    waiter.lst.del();
    waiter.lst.setup();
    waiter.woken = true;
    const t = waiter.task;
    if (t.state != .STOPPED and t.state != .ZOMBIE) {
        t.wakeup_time = 0;
        t.state = .RUNNING;
    }
}

fn futexWake(
    uaddr: ?*u32,
    flags: u32,
    val: u32,
    bitset: u32,
) !u32 {
    const user_addr = uaddr orelse
        return errors.EFAULT;
    if (val == 0)
        return 0;

    const queue = getQueue(
        FutexKey.init(user_addr, flags)
    ) orelse
        return 0;

    var woken: u32 = 0;
    {
        const qstate = queue.lock.lock_irq_disable();
        defer queue.lock.unlock_irq_enable(qstate);

        var it = queue.waiters.iterator();
        _ = it.next();
        while (it.next()) |i| {
            if (woken >= val)
                break;
            const node = i.curr;
            const w = node.entry(FutexWaiter, "lst");
            if ((w.bitset & bitset) == 0)
                continue;
            i.curr = node.prev orelse &queue.waiters;
            wakeWaiter(w);
            woken += 1;
        }
    }
    return woken;
}

fn futexRequeue(
    uaddr: ?*u32,
    flags: u32,
    wake_count: u32,
    requeue_count: u32,
    uaddr2: ?*u32,
) !u32 {
    const src_user = uaddr orelse
        return errors.EFAULT;
    const dst_user = uaddr2 orelse
        return errors.EFAULT;

    const src = getQueue(
        FutexKey.init(src_user, flags)
    ) orelse
        return 0;
    const dst = try getOrCreateQueue(
        FutexKey.init(dst_user, flags)
    );

    var woken: u32 = 0;

    const lock_state = src.lock.lock_irq_disable();
    defer src.lock.unlock_irq_enable(lock_state);
    if (dst != src) dst.lock.lock();
    defer if (dst != src) dst.lock.unlock();

    var it = src.waiters.iterator();
    _ = it.next();
    while (it.next()) |i| {
        if (woken >= wake_count)
            break;
        const node = i.curr;
        const w = node.entry(FutexWaiter, "lst");
        i.curr = node.prev orelse &src.waiters;
        wakeWaiter(w);
        woken += 1;
    }

    if (src != dst and requeue_count != 0) {
        var moved: u32 = 0;
        var _it = src.waiters.iterator();
        _ = _it.next();
        while (_it.next()) |i| {
            if (moved >= requeue_count)
                break;
            const node = i.curr;
            const w = node.entry(FutexWaiter, "lst");
            i.curr = node.prev orelse &src.waiters;
            w.lst.del();
            w.lst.setup();
            dst.waiters.addTail(&w.lst);
            w.queue = dst;
            moved += 1;
        }
    }
    return woken;
}

fn getFlags(op: u32) u32 {
    var flags: u32 = 0;
    if (op & FUTEX_PRIVATE_FLAG == 0)
        flags |= FLAGS_SHARED;
    if (op & FUTEX_CLOCK_REALTIME != 0)
        flags |= FLAGS_CLOCKRT;
    return flags;
}

fn doFutex(
    uaddr: ?*u32,
    op: u32,
    val: u32,
    utime: ?*krn.time.kernel_timespec,
    uaddr2: ?*u32,
    val3: u32,
) !u32 {
    const cmd: u32 = op & FUTEX_CMD_MASK;
    const flags: u32 = getFlags(op);
    if (flags & FLAGS_CLOCKRT != 0) {
        if (cmd != FUTEX_WAIT_BITSET
            and cmd != FUTEX_WAIT_REQUEUE_PI
            and cmd != FUTEX_LOCK_PI2)
            return errors.ENOSYS;
    }
    if (flags & FLAGS_CLOCKRT != 0)
        return errors.ENOSYS;
    return switch (cmd) {
        FUTEX_WAIT => futexWait(
            uaddr, flags, val,
            utime, FUTEX_BITSET_MATCH_ANY
        ),
        FUTEX_WAIT_BITSET => blk: {
            if (val3 == 0)
                break :blk errors.EINVAL;
            break :blk futexWait(
                uaddr, flags, val,
                utime, val3
            );
        },
        FUTEX_WAKE => futexWake(
            uaddr, flags, val, FUTEX_BITSET_MATCH_ANY
        ),
        FUTEX_WAKE_BITSET => blk: {
            if (val3 == 0)
                break :blk errors.EINVAL;
            break :blk futexWake(uaddr, flags, val, val3);
        },
        FUTEX_REQUEUE => futexRequeue(
            uaddr, flags, val,
            @intFromPtr(utime), uaddr2
        ),
        else => errors.ENOSYS,
    };
}

pub fn futex(
    uaddr: ?*u32,
    op: u32,
    val: u32,
    utime: ?*krn.time.kernel_timespec,
    uaddr2: ?*u32,
    val3: u32,
) !u32 {
    return try doFutex(
        uaddr, op, val,
        utime, uaddr2, val3
    );
}
