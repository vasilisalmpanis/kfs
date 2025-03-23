const std = @import("std");
const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");
const tree = @import("../utils/tree.zig");
const Regs = @import("arch").Regs;
const currentMs = @import("../time/jiffies.zig").currentMs;
const reschedule = @import("./scheduler.zig").reschedule;
const printf = @import("debug").printf;
const mutex = @import("./mutex.zig").Mutex;

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
pub const TSS = packed struct {
    back_link: u16,
    esp0: usize,
    ss0: u16,
    esp1: usize,
    ss1: u16,
    esp2: usize,
    ss2: u16,
    cr3: usize,
    eip: usize,
    eflags: usize,
    eax: usize,
    ecx: usize,
    edx: usize,
    ebx: usize,
    esp: usize,
    ebp: usize,
    esi: usize,
    edi: usize,
    es: u16,
    cs: u16,
    ss: u16,
    ds: u16,
    fs: u16,
    gs: u16,
    ldt: u16,
    trace: u16,
    bitmap: u16,

    pub fn init() TSS {
        return TSS {
            .back_link = 0,
            .esp0 = 0,
            .ss0 = 0,
            .esp1 = 0,
            .ss1 = 0,
            .esp2 = 0,
            .ss2 = 0,
            .cr3= 0 ,
            .eip= 0 ,
            .eflags = 0,
            .eax = 0,
            .ecx = 0,
            .edx = 0,
            .ebx = 0,
            .esp = 0,
            .ebp = 0,
            .esi = 0,
            .edi = 0,
            .es = 0,
            .cs = 0,
            .ss = 0,
            .ds = 0,
            .fs = 0,
            .gs = 0,
            .ldt = 0,
            .trace = 0,
            .bitmap = 0,
        };
    }
};

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
