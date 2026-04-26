const std = @import("std");
const arch = @import("arch");
const fpu = @import("arch").fpu;
const krn = @import("../main.zig");
const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");
const tree = @import("../utils/tree.zig");
const Regs = @import("arch").Regs;
const currentMs = @import("../time/jiffies.zig").currentMs;
const reschedule = @import("./scheduler.zig").reschedule;
const printf = @import("debug").printf;
const signal = @import("./signals.zig");
const ThreadHandler = @import("./kthread.zig").ThreadHandler;
const mm = @import("../mm/init.zig");
const errors = @import("../syscalls/error-codes.zig").PosixError;

var pid_bitset = std.bit_set.ArrayBitSet(
    usize,
    std.math.maxInt(u16) + 1
).initEmpty();
var pid_lock = krn.Spinlock.init();
pub var pid_it: std.bit_set.ArrayBitSet(usize, std.math.maxInt(u16)).Iterator(.{
    .direction = .forward,
    .kind = .unset,
}) = undefined;

pub fn allocPid() !u16 {
    const lock_state = pid_lock.lock_irq_disable();
    defer pid_lock.unlock_irq_enable(lock_state);

    if (
        pid_it.words_remain.len == 0
        and pid_it.bits_remain == 0
    ) {
        pid_it = pid_bitset.iterator(.{
            .direction = .forward,
            .kind = .unset,
        });
    }
    if (pid_it.next()) |_pid| {
        pid_bitset.set(_pid);
        return @intCast(_pid);
    }
    return error.EAGAIN;
}

pub fn releasePid(_pid: u16) void {
    const lock_state = pid_lock.lock_irq_disable();
    defer pid_lock.unlock_irq_enable(lock_state);

    pid_bitset.unset(_pid);
}

pub const TaskState = enum(u8) {
    RUNNING,
    UNINTERRUPTIBLE_SLEEP,  // Sleep the whole duration
    INTERRUPTIBLE_SLEEP,    // IO finished? wake up
    STOPPED,
    ZOMBIE,
};

pub const TaskType = enum(u8) {
    KTHREAD,
    PROCESS,
};

pub const RefCount = struct {
    count: std.atomic.Value(usize),
    dropFn: *const fn (*RefCount) void,

    pub fn init() RefCount {
        return .{
            .count = std.atomic.Value(usize).init(0),
            .dropFn = RefCount.noop,
        };
    }

    pub fn get(rc: *RefCount) void {
        // no synchronization necessary; just updating a counter.
        _ = rc.count.fetchAdd(1, .monotonic);
    }

    pub fn put(rc: *RefCount) void {
        // release ensures code before unref() happens-before the
        // count is decremented as dropFn could be called by then.
        if (rc.getValue() == 0)
            @panic("Underflow\n");
        if (rc.count.fetchSub(1, .release) == 1) {
            // seeing 1 in the counter means that other unref()s have happened,
            // but it doesn't mean that uses before each unref() are visible.
            // The load acquires the release-sequence created by previous unref()s
            // in order to ensure visibility of uses before dropping.
            _ = rc.count.load(.acquire);
            (rc.dropFn)(rc);
        }
    }

    pub fn getValue(rc: *RefCount) usize {
        return rc.count.load(.monotonic);
    }

    pub fn isFree(rc: *RefCount) bool {
        return rc.getValue() == 0;
    }

    fn noop(rc: *RefCount) void {
        _ = rc;
    }
};


pub const MAX_GROUPS: usize = 32;

// Task is the basic unit of scheduling
// both threads and processes are tasks
// and threads share
//

// Task
// Anyone using this struct must get refcount
// and put it when no longer needed.
pub const Task = struct {

    pid:            u16,
    tsktype:        TaskType,
    name:           [16] u8,
    uid:            u16,
    gid:            u16,
    groups:         [MAX_GROUPS]u16 = .{0} ** MAX_GROUPS,
    groups_count:   u8              = 0,
    pgid:           u16             = 1,
    sid:            u16             = 1,
    ctty:           ?*krn.fs.File   = null,
    stack_bottom:   usize,
    state:          TaskState       = TaskState.RUNNING,
    regs:           Regs            = Regs.init(),
    tls:            u32             = 0,
    limit:          u32             = 0,

    // FPU state for context switching
    fpu_state:      ?*fpu.FPUState  = null,
    fpu_used:       bool            = false,
    save_fpu_state: bool            = false,

    tree:           tree.TreeNode   = tree.TreeNode.init(),
    list:           lst.ListHead    = lst.ListHead.init(),
    refcount:       RefCount        = RefCount.init(),
    wakeup_time:    usize           = 0,

    utime:          u32             = 0,
    stime:          u32             = 0,

    mm:             ?*mm.MM         = null,
    // Filesystem Info
    fs:             *krn.fs.FSInfo,
    // Open files info
    files:          *krn.fs.TaskFiles,

    // signals
    sighand:        ?*signal.SigHand     = null,
    sigmask:        signal.sigset_t      = signal.sigset_t.init(),
    wait_wq:        krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),

    // only for kthreads
    threadfn:       ?ThreadHandler       = null,
    arg:            ?*const anyopaque    = null,
    result:         i32                  = 0,
    should_stop:    bool                 = false,

    pub fn init(uid: u16, gid: u16, pgid: u16, tp: TaskType) Task {
        return Task{
            .pid = 0,
            .uid = uid,
            .gid = gid,
            .groups = .{0} ** MAX_GROUPS,
            .groups_count = 0,
            .pgid = pgid,
            .sid = pgid,
            .ctty = null,
            .stack_bottom = 0,
            .tsktype = tp,
            .fs = undefined,
            .files = undefined,
            .tls = 0,
            .limit = 0,
            .name = .{0} ** 16,
            .should_stop = false,
            .utime = 0,
            .stime = 0,
        };
    }

    pub fn inGroup(self: *const Task, group_id: u32) bool {
        if (group_id > std.math.maxInt(u16))
            return false;
        const gid16: u16 = @intCast(group_id);
        if (self.gid == gid16)
            return true;
        const count: usize = self.groups_count;
        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            if (self.groups[idx] == gid16)
                return true;
        }
        return false;
    }

    pub fn setup(self: *Task, task_stack_top: usize, task_stack_bottom: usize, name: []const u8) !void {
        try self.assignPID();
        self.uid = 0;
        self.regs.setStackPointer(task_stack_top);
        self.stack_bottom = task_stack_bottom;
        self.list.setup();
        self.tree.setup();
        self.refcount = RefCount.init();
        self.fpu_used = false;
        self.save_fpu_state = false;
        self.fpu_state = null;
        self.mm = &mm.proc_mm.init_mm;
        self.utime = 0;
        self.stime = 0;
        self.setName(name);
        self.wait_wq.setup();
        self.should_stop = false;
    }

    pub fn setName(self: *Task, name: []const u8) void {
        const len = if (name.len >= 15) 15 else name.len;
        self.name = .{0} ** 16;
        @memcpy(self.name[0..len], name[0..len]);
    }

    pub fn new(
        task_stack_top: u32,
        stack_btm: u32,
        uid: u16,
        gid: u16,
        pgid: u16,
        tp: TaskType,
        name: []const u8,
    ) anyerror!*Task {
        if (krn.mm.kmalloc(Task)) |task| {
            errdefer krn.mm.kfree(task);
            try task.assignPID();
            try task.initSelf(task_stack_top, stack_btm, uid, gid, pgid, tp, name);
            return task;
        }
        return error.OutOfMemory;
    }

    pub fn initSelf(
        self: *Task,
        task_stack_top: usize,
        stack_btm: usize,
        uid: u16,
        gid: u16,
        pgid: u16,
        tp: TaskType,
        name: []const u8,
    ) !void {
        const tmp = Task.init(uid, gid, pgid, tp);
        self.uid = tmp.uid;
        self.gid = tmp.gid;
        self.groups_count = current.groups_count;
        @memcpy(
            self.groups[0..MAX_GROUPS],
            current.groups[0..MAX_GROUPS]
        );
        self.pgid = tmp.pgid;
        self.sid = current.sid;
        self.ctty = current.ctty;
        if (self.ctty) |ctty| {
            ctty.ref.get();
        }
        self.state = tmp.state;
        self.refcount = tmp.refcount;
        self.refcount.get();
        self.wakeup_time = tmp.wakeup_time;
        self.utime = tmp.utime;
        self.stime = tmp.stime;
        self.stack_bottom = tmp.stack_bottom;
        self.tsktype = tmp.tsktype;
        self.save_fpu_state = tmp.save_fpu_state;
        self.fpu_used = tmp.fpu_used;
        self.fpu_state = tmp.fpu_state;
        self.should_stop = tmp.should_stop;

        self.regs = Regs.init();
        self.tree = tree.TreeNode.init();
        self.list = lst.ListHead.init();
        self.regs.setStackPointer(task_stack_top);
        self.stack_bottom = stack_btm;
        self.list.setup();
        self.tree.setup();

        self.setName(name);
        self.sigmask = current.sigmask;
        self.wait_wq = krn.wq.WaitQueueHead.init();
        self.wait_wq.setup();

        // We should create proc files here because if we do before
        // we could have the following sequence.
        // - newProcess creates the files and refs the task
        // - initSelf runs and sets task.refcount to 1.
        // - proc destroyInode unrefs the task and we get underflow.
        if (self.tsktype == .PROCESS) {
            try krn.fs.procfs.newProcess(self);
        }
        const lock_state = tasks_lock.lock_irq_disable();
        defer tasks_lock.unlock_irq_enable(lock_state);

        current.tree.addChild(&self.tree);
        current.list.addTail(&self.list);
    }

    fn zombifyChildren(self: *Task) void {
        if (self.tree.child) |ch| {
            var it = ch.siblingsIterator();
            while (it.next()) |i| {
                i.curr.entry(Task, "tree").*.state = .ZOMBIE;
            }
        }
    }

    pub fn delFromTree(self: *Task) void {
        // self.zombifyChildren();
        self.tree.del();
    }

    pub fn assignPID(self: *Task) !void {
        self.pid = try allocPid();
    }

    fn findByPidRec(self: *Task, task_pid: u16) ?*Task {
        if (self.pid == task_pid) {
            self.refcount.get();
            return self;
        }

        var res: ?*Task = null;
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                res = i.curr.entry(Task, "tree").*.findByPidRec(task_pid);
                if (res != null)
                    break ;
            }
        }
        return res;
    }

    pub fn findByPid(self: *Task, task_pid: u16) ?*Task {
        if (self.pid == task_pid) {
            self.refcount.get();
            return self;
        }

        const lock_state = tasks_lock.lock_irq_disable();
        defer tasks_lock.unlock_irq_enable(lock_state);

        var res: ?*Task = null;
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                res = i.curr.entry(Task, "tree").*.findByPidRec(task_pid);
                if (res != null)
                    break ;
            }
        }
        return res;
    }

    pub fn refcountChildren(self: *Task, pgid: u32, ref: bool) bool {
        var result: bool = false;
        const lock_state = tasks_lock.lock_irq_disable();
        defer tasks_lock.unlock_irq_enable(lock_state);
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                const res = i.curr.entry(Task, "tree");
                if ((pgid > 0 and res.pgid == pgid) or pgid == 0) {
                    if (res.state != .STOPPED) {
                        result = true;
                        if (ref) {
                            res.refcount.get();
                        } else {
                            res.refcount.put();
                        }
                    }
                }
            }
        }
        return result;
    }

    pub fn findChildByPid(self: *Task, task_pid: u16) ?*Task {
        const lock_state = tasks_lock.lock_irq_disable();
        defer tasks_lock.unlock_irq_enable(lock_state);
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                const res = i.curr.entry(Task, "tree");
                if (res.pid == task_pid) {
                    res.refcount.get();
                    return res;
                }
            }
        }
        return null;
    }

    pub fn setControllingTTY(self: *Task, file: *krn.fs.File) void {
        if (self.ctty == file)
            return;
        self.clearControllingTTY();
        file.ref.get();
        self.ctty = file;
    }

    pub fn clearControllingTTY(self: *Task) void {
        if (self.ctty) |ctty| {
            ctty.ref.put();
            self.ctty = null;
        }
    }

    pub fn controllingTTY(self: *Task) ?*krn.fs.File {
        return self.ctty;
    }

    pub fn releaseSharedResources(self: *Task) void {
        self.clearControllingTTY();
        self.files.deinit();
        self.fs.deinit();


        const sighand = self.getSighandOrPanic();
        sighand.ref.put();
        self.sighand = null;

        self.sighand = null;
        if (self.mm) |_mm| {
            _mm.releaseMappings();
        }
        if (self.fpu_state) |state| {
            self.fpu_used = false;
            krn.mm.kfree(state);
            self.fpu_state = null;
        }
    }

    /// tasks_locked defines if tasks_lock is already locked
    pub fn finish(self: *Task, tasks_locked: bool) void {
        if (self.state != .ZOMBIE and self.state != .STOPPED)
            return ;
        self.state = .STOPPED;
        const lock_state = if (!tasks_locked) tasks_lock.lock_irq_disable() else false;
        defer if (!tasks_locked) tasks_lock.unlock_irq_enable(lock_state);

        self.list.del();
        self.refcount.put();
        if (self.refcount.getValue() > 0) {
            krn.logger.ERROR("[PID: {d}] is exiting and is extra referenced", .{self.pid});
            @panic("exiting task being used");
        }
        if (stopped_tasks == null) {
            stopped_tasks = &self.list;
            stopped_tasks.?.setup();
        } else {
            stopped_tasks.?.addTail(&self.list);
        }
    }

    pub fn wakeupParent(self: *Task, tasks_locked: bool) void {
        const lock_state = if (!tasks_locked) tasks_lock.lock_irq_disable() else false;
        defer if (!tasks_locked) tasks_lock.unlock_irq_enable(lock_state);

        if (self.tree.parent) |_p| {
            const parent = _p.entry(Task, "tree");
            parent.refcount.get();
            parent.wait_wq.wakeUpOne();
            parent.refcount.put();
        }
    }

    pub fn dbgPrint(self: *Task) void {
        krn.logger.ERROR(
            \\ Task {d}
            \\   name: {s}
            \\   uid: {d}
            \\   gid: {d}
            \\   pgid: {d}
            \\   sid: {d}
            \\   tsktype: {t}
            \\   state: {t}
            \\   fpu_state: 0x{x:0>8}
            \\   fpu_used: {any}
            \\   mm: 0x{x:0>8}
            \\   fs: 0x{x:0>8}
            \\   files: 0x{x:0>8}
            \\   stack_bottom: 0x{x:0>8}
            \\   tls: 0x{x:0>8}
            \\   limit: {d}
            \\   list->next: {x}
            \\   list->prev: {x}
            \\   tree->parent: {x}
            \\
            , .{
                self.pid,
                self.name[0..16],
                self.uid,
                self.gid,
                self.pgid,
                self.sid,
                self.tsktype,
                self.state,
                @intFromPtr(self.fpu_state),
                self.fpu_used,
                @intFromPtr(self.mm),
                @intFromPtr(self.fs),
                @intFromPtr(self.files),
                self.stack_bottom,
                self.tls,
                self.limit,
                @intFromPtr(self.list.next),
                @intFromPtr(self.list.prev),
                @intFromPtr(self.tree.parent)
            }
        );
    }

    pub fn getSighandOrPanic(self: *Task) *krn.signals.SigHand {
        const sighand = self.sighand orelse {
            @panic("No userspace task should have sighand == NULL\n");
        };
        return sighand;
    }

    pub fn hasPendingSignal(self: *Task) bool {
        return self.getSighandOrPanic().hasPending();
    }
};

pub fn sleep(millis: usize) void {
    if (current == &initial_task)
        return ;
    current.wakeup_time = currentMs() + millis;
    current.state = .UNINTERRUPTIBLE_SLEEP;
    reschedule();
}

pub var initial_task = Task.init(0, 0, 1, .KTHREAD);
pub var current = &initial_task;
pub var tasks_lock: krn.Spinlock = krn.Spinlock.init();
pub var stopped_tasks: ?*lst.ListHead = null;

extern const stack_top: u32;
extern const stack_bottom: u32;

var inital_fpu_state = arch.fpu.FPUState{};

pub fn initMultitasking() void {
    pid_it = pid_bitset.iterator(.{
        .direction = .forward,
        .kind = .unset,
    });
    initial_task.setup(
        @intFromPtr(&stack_top),
        @intFromPtr(&stack_bottom),
        "swapper"
    ) catch |err| {
        krn.logger.ERROR("initMultitasking(): {t}", .{err});
        @panic("Failed to setup initial task!");
    };
    initial_task.refcount.get();
    initial_task.mm.?.vas = @intFromPtr(&vmm.initial_page_dir) - krn.mm.PAGE_OFFSET;
    initial_task.fpu_state = &inital_fpu_state;
    krn.irq.registerHandler(0, &krn.timerHandler, null);
    arch.system.enableWriteProtect();
}
