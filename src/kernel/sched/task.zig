const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");
const regs = @import("arch").regs;
const current_ms = @import("../time/jiffies.zig").current_ms;
const reschedule = @import("./scheduler.zig").reschedule;
const printf = @import("debug").printf;
const mutex = @import("./mutex.zig").Mutex;

var pid: u32 = 0;

const task_state = enum(u8) {
    RUNNING,
    UNINTERRUPTIBLE_SLEEP,  // Sleep the whole duration
    INTERRUPTIBLE_SLEEP,    // IO finished? wake up
    STOPPED,
    ZOMBIE,
};

const task_type = enum(u8) {
    KTHREAD,
    PROCESS,
};
// Task is the basic unit of scheduling
// both threads and processes are tasks
// and threads share 
//
pub const tss_struct = packed struct {
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

    pub fn init() tss_struct {
        return tss_struct {
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

// task_struct
// Anyone using this struct must get refcount
// and put it when no longer needed.
pub const task_struct = struct {
    pid:            u32,
    type:           task_type,
    virtual_space:  u32,
    uid:            u16,
    gid:            u16,
    stack_bottom:   u32,
    state:          task_state      = task_state.RUNNING,
    regs:           regs            = regs.init(),
    children:       lst.ListHead    = lst.ListHead.init(),
    siblings:       lst.ListHead    = lst.ListHead.init(),
    parent:         ?*task_struct   = null,
    list:           lst.ListHead    = lst.ListHead.init(),
    refcount:       u32             = 0,
    wakeup_time:    usize           = 0,

    // only for kthreads
    threadfn:       ?*const fn (arg: ?*const anyopaque) i32 = null,
    arg:            ?*const anyopaque                       = null,
    result:         i32                                     = 0,
    should_stop:    bool                                    = false,

    pub fn init(virt: u32, uid: u16, gid: u16, tp: task_type) task_struct {
        return task_struct{
            .pid = 0,
            .virtual_space = virt,
            .uid = uid,
            .gid = gid,
            .stack_bottom = 0,
            .type = tp,
        };
    }

    pub fn setup(self: *task_struct, virt: u32, task_stack_top: u32) void {
        self.virtual_space = virt;
        self.pid = pid;
        pid += 1;
        self.regs.esp = task_stack_top;
        self.parent = self;
        self.children.setup();
        self.siblings.setup();
        self.list.setup();
    }

    pub fn init_self(
        self: *task_struct,
        virt: u32,
        task_stack_top: u32,
        stack_bottom: u32,
        uid: u16,
        gid: u16,
        tp: task_type
    ) void {
        tasks_mutex.lock();
        const tmp = task_struct.init(virt, uid, gid, tp);
        self.pid = tmp.pid;
        self.regs.esp = task_stack_top;
        self.virtual_space = tmp.virtual_space;
        self.state = tmp.state;
        self.uid = tmp.uid;
        self.gid = tmp.gid;
        self.pid = pid;
        pid += 1;
        self.list.setup();
        self.stack_bottom = stack_bottom;
        current.list.add_tail(&self.list);

        // tree logic
        self.siblings.setup();
        self.children.setup();
        current.add_child(self);
        tasks_mutex.unlock();
    }

    pub fn add_child(parent: *task_struct, child: *task_struct) void {
        if (parent.children.next.? != &parent.children) {
            parent.children.next.?.add(&child.siblings);
        } else {
            parent.children.next = &child.siblings;
            parent.children.prev = &child.siblings;
        }
        child.parent = parent;
    }

    /// Should only be called in scheduler.
    pub fn remove_self(self: *task_struct) void {
        const parent: *task_struct = self.parent.?;

        if (self == &initial_task)
            return ;

        if (!self.siblings.is_single()) {
            parent.children.next = self.siblings.next;
            parent.children.prev = self.siblings.prev;
            self.siblings.del();
        } else {
            parent.children.next = &parent.children;
            parent.children.prev = &parent.children;
            // if we are child of initial_task we already removed ourselfs from the list
        }

        if (!self.children.is_single()) {
            const first_child: *lst.ListHead = self.children.next.?;
            const first_child_next: *lst.ListHead = self.children.next.?.next.?;

            var it = first_child.iterator();
            while (it.next()) |i| {
                i.curr.entry(task_struct, "siblings").*.state = .ZOMBIE;
            }
            
            if (initial_task.children.is_single()) {
                initial_task.children.next = first_child;
                initial_task.children.prev = first_child;
            } else {
                const child: *lst.ListHead = initial_task.children.next.?;
                const child_prev: *lst.ListHead = initial_task.children.next.?.prev.?;
                child.prev = first_child;
                first_child.next = child;
                child_prev.next = first_child_next;
                first_child_next.prev = child_prev;
            }
        }
    }
};

pub fn sleep(millis: usize) void {
    if (current == &initial_task)
        return ;
    current.wakeup_time = current_ms() + millis;
    current.state = .UNINTERRUPTIBLE_SLEEP;
    reschedule();
}

pub var initial_task = task_struct.init(0, 0, 0, .KTHREAD);
pub var current = &initial_task;
pub var tasks_mutex: mutex = mutex.init();
pub var stopped_tasks: ?*lst.ListHead = null;
