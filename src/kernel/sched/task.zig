const std = @import("std");
const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");
const tree = @import("../utils/tree.zig");
const Regs = @import("arch").Regs;
const currentMs = @import("../time/jiffies.zig").currentMs;
const reschedule = @import("./scheduler.zig").reschedule;
const printf = @import("debug").printf;
const mutex = @import("./mutex.zig").Mutex;
const signal = @import("./signals.zig");

var pid: u32 = 0;

const TaskState = enum(u8) {
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
    virtual_space:  u32,
    uid:            u16,
    gid:            u16,
    stack_bottom:   u32,
    state:          TaskState       = TaskState.RUNNING,
    regs:           Regs            = Regs.init(),
    tree:           tree.TreeNode   = tree.TreeNode.init(),
    list:           lst.ListHead    = lst.ListHead.init(),
    refcount:       u32             = 0,
    wakeup_time:    usize           = 0,

    // signals
    sig_pending:    u32                 = 0,
    sigaction:      signal.SigAction    = signal.SigAction.init(),
    sigmask:        u32                 = 0,

    // only for kthreads
    threadfn:       ?*const fn (arg: ?*const anyopaque) i32 = null,
    arg:            ?*const anyopaque                       = null,
    result:         i32                                     = 0,
    should_stop:    bool                                    = false,

    pub fn init(virt: u32, uid: u16, gid: u16, tp: TaskType) Task {
        return Task{
            .pid = 0,
            .virtual_space = virt,
            .uid = uid,
            .gid = gid,
            .stack_bottom = 0,
            .tsktype = tp,
        };
    }

    pub fn setup(self: *Task, virt: u32, task_stack_top: u32) void {
        self.virtual_space = virt;
        self.pid = pid;
        pid += 1;
        self.regs.esp = task_stack_top;
        self.list.setup();
        self.tree.setup();
        self.refcount = 0;
    }

    pub fn initSelf(
        self: *Task,
        virt: u32,
        task_stack_top: u32,
        stack_bottom: u32,
        uid: u16,
        gid: u16,
        tp: TaskType
    ) void {
        const tmp = Task.init(virt, uid, gid, tp);
        self.uid = tmp.uid;
        self.gid = tmp.gid;
        self.state = tmp.state;
        self.refcount = tmp.refcount;
        self.wakeup_time = tmp.wakeup_time;
        self.virtual_space = tmp.virtual_space;
        self.stack_bottom = tmp.stack_bottom;
        self.tsktype = tmp.tsktype;

        self.regs = Regs.init();
        self.tree = tree.TreeNode.init();
        self.list = lst.ListHead.init();
        self.regs.esp = task_stack_top;
        self.stack_bottom = stack_bottom;
        self.pid = pid;
        pid += 1;
        self.list.setup();
        self.tree.setup();

        self.sig_pending = 0;
        self.sigaction = signal.SigAction.init();
        self.sigmask = 0;

        tasks_mutex.lock();
        current.list.addTail(&self.list);
        current.tree.addChild(&self.tree);
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
        self.zombifyChildren();
        self.tree.del();
    }

    pub fn findByPid(self: *Task, task_pid: u32) ?*Task {
        if (self.pid == task_pid)
            return self;
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
};

pub fn sleep(millis: usize) void {
    if (current == &initial_task)
        return ;
    current.wakeup_time = currentMs() + millis;
    current.state = .UNINTERRUPTIBLE_SLEEP;
    reschedule();
}

pub var initial_task = Task.init(0, 0, 0, .KTHREAD);
pub var current = &initial_task;
pub var tasks_mutex: mutex = mutex.init();
pub var stopped_tasks: ?*lst.ListHead = null;
