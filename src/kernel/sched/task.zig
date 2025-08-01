const std = @import("std");
const arch = @import("arch");
const krn = @import("../main.zig");
const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");
const tree = @import("../utils/tree.zig");
const Regs = @import("arch").Regs;
const currentMs = @import("../time/jiffies.zig").currentMs;
const reschedule = @import("./scheduler.zig").reschedule;
const printf = @import("debug").printf;
const mutex = @import("./mutex.zig").Mutex;
const signal = @import("./signals.zig");
const ThreadHandler = @import("./kthread.zig").ThreadHandler;
const mm = @import("../mm/init.zig");
const errors = @import("../syscalls/error-codes.zig").PosixError;

var pid: u32 = 0;

pub const TaskState = enum(u8) {
    RUNNING,
    UNINTERRUPTIBLE_SLEEP,  // Sleep the whole duration
    INTERRUPTIBLE_SLEEP,    // IO finished? wake up
    STOPPED,
    ZOMBIE,
};

const TaskType = enum(u8) {
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

    pub fn ref(rc: *RefCount) void {
        // no synchronization necessary; just updating a counter.
        _ = rc.count.fetchAdd(1, .monotonic);
    }

    pub fn unref(rc: *RefCount) void {
        // release ensures code before unref() happens-before the
        // count is decremented as dropFn could be called by then.
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


// Task is the basic unit of scheduling
// both threads and processes are tasks
// and threads share 
//

// Task
// Anyone using this struct must get refcount
// and put it when no longer needed.
pub const Task = struct {
    pid:            u32,
    tsktype:        TaskType,
    uid:            u16,
    gid:            u16,
    pgid:           u16             = 1,
    stack_bottom:   u32,
    state:          TaskState       = TaskState.RUNNING,
    regs:           Regs            = Regs.init(),

    tree:           tree.TreeNode   = tree.TreeNode.init(),
    list:           lst.ListHead    = lst.ListHead.init(),
    refcount:       RefCount        = RefCount.init(),
    wakeup_time:    usize           = 0,

    mm:             ?*mm.MM              = null,
    // Filesystem Info
    fs:             *krn.fs.FSInfo,
    // Open files info
    files:          *krn.fs.TaskFiles,

    // signals
    sighand:        signal.SigHand       = signal.SigHand.init(),
    sigmask:        signal.sigset_t      = signal.sigset_t.init(),

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
            .pgid = pgid,
            .stack_bottom = 0,
            .tsktype = tp,
            .fs = undefined,
            .files = undefined,
        };
    }

    pub fn setup(self: *Task, virt: u32, task_stack_top: u32, task_stack_bottom: u32) void {
        self.pid = pid;
        self.uid = 0;
        pid += 1;
        self.regs.esp = task_stack_top;
        self.stack_bottom = task_stack_bottom;
        self.list.setup();
        self.tree.setup();
        self.refcount = RefCount.init();
        self.mm = &mm.proc_mm.init_mm;
        mm.proc_mm.init_mm.vas = virt;
    }

    pub fn new(
        task_stack_top: u32,
        stack_btm: u32,
        uid: u16,
        gid: u16,
        pgid: u16,
        tp: TaskType
    ) anyerror!*Task {
        if (krn.mm.kmalloc(Task)) |task| {
            errdefer krn.mm.kfree(task);
            try task.initSelf(task_stack_top, stack_btm, uid, gid, pgid, tp);
            return task;
        }
        return error.OutOfMemory;
    }

    pub fn initSelf(
        self: *Task,
        task_stack_top: u32,
        stack_btm: u32,
        uid: u16,
        gid: u16,
        pgid: u16,
        tp: TaskType
    ) !void {
        const tmp = Task.init(uid, gid, pgid, tp);
        self.uid = tmp.uid;
        self.gid = tmp.gid;
        self.pgid = tmp.pgid;
        self.state = tmp.state;
        self.refcount = tmp.refcount;
        self.wakeup_time = tmp.wakeup_time;
        self.stack_bottom = tmp.stack_bottom;
        self.tsktype = tmp.tsktype;

        self.regs = Regs.init();
        self.tree = tree.TreeNode.init();
        self.list = lst.ListHead.init();
        self.regs.esp = task_stack_top;
        self.stack_bottom = stack_btm;
        self.pid = pid;
        pid += 1;
        self.list.setup();
        self.tree.setup();

        self.sighand = current.sighand;
        self.sighand.pending = std.StaticBitSet(32).initEmpty();

        if (tp != .KTHREAD) { // For now
            if (krn.fs.TaskFiles.new()) |files| {
                try files.dup(current.files);
                self.files = files;
            } else {
                return errors.ENOMEM;
            }
        }

        tasks_mutex.lock();
        current.tree.addChild(&self.tree);
        current.list.addTail(&self.list);
        tasks_mutex.unlock();
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

    pub fn findByPid(self: *Task, task_pid: u32) ?*Task {
        if (self.pid == task_pid) {
            self.refcount.ref();
            return self;
        }
        var res: ?*Task = null;
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                res = i.curr.entry(Task, "tree").*.findByPid(task_pid);
                if (res != null)
                    break ;
            }
        }
        return res;
    }

    pub fn refcountChildren(self: *Task, pgid: u32, ref: bool) bool {
        var result: bool = false;
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                const res = i.curr.entry(Task, "tree");
                if ((pgid > 0 and res.pgid == pgid) or pgid == 0) {
                    result = true;
                    if (ref) {
                        res.refcount.ref();
                    } else {
                        res.refcount.unref();
                    }
                }
            }
        }
        return result;
    }

    pub fn findChildByPid(self: *Task, task_pid: u32) ?*Task {
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                const res = i.curr.entry(Task, "tree");
                if (res.pid == task_pid) {
                    res.refcount.ref();
                    return res;
                }
            }
        }
        return null;
    }

    pub fn finish(self: *Task) void {
        self.state = .STOPPED;
        tasks_mutex.lock();
        self.list.del();
        if (stopped_tasks == null) {
            stopped_tasks = &self.list;
            stopped_tasks.?.setup();
        } else {
            stopped_tasks.?.addTail(&self.list);
        }
        tasks_mutex.unlock();
        if (self == current)
            reschedule();
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
pub var tasks_mutex: mutex = mutex.init();
pub var stopped_tasks: ?*lst.ListHead = null;

extern const stack_top: u32;
extern const stack_bottom: u32;

pub fn initMultitasking() void {
    initial_task.setup(
        @intFromPtr(&vmm.initial_page_dir) - krn.mm.PAGE_OFFSET,
        @intFromPtr(&stack_top),
        @intFromPtr(&stack_bottom),
    );
    krn.irq.registerHandler(0, &krn.timerHandler);
    arch.system.enableWriteProtect();
}
