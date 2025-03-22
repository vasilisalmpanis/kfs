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
    virtual_space:  u32,
    uid:            u16,
    gid:            u16,
    state:          task_state,
    regs:           regs,
    stack_bottom:   u32,
    children:       lst.list_head,
    siblings:       lst.list_head,
    parent:         ?*task_struct,
    next:           ?*task_struct,
    type:           task_type,
    refcount:       u32 = 0,
    wakeup_time:    usize = 0,

    // only for kthreads
    threadfn:       ?*const fn (arg: ?*const anyopaque) i32 = null,
    arg:            ?*const anyopaque = null,
    result:         i32 = 0,
    should_stop:    bool = false,

    pub fn init(virt: u32, uid: u16, gid: u16, tp: task_type) task_struct {
        return task_struct{
            .pid = 0,
            .virtual_space = virt,
            .state = task_state.RUNNING,
            .uid = uid,
            .gid = gid,
            .regs = regs.init(),
            .stack_bottom = 0,
            .children = .{ .prev = null , .next = null},
            .siblings = .{ .prev = null , .next = null},
            .parent = null,
            .next = null,
            .type = tp,
        };
    }

    pub fn setup(self: *task_struct, virt: u32, task_stack_top: u32) void {
        self.virtual_space = virt;
        self.pid = pid;
        pid += 1;
        self.regs.esp = task_stack_top;
        self.parent = self;
        self.children = .{.prev = &self.children, .next = &self.children};
        self.siblings = .{.prev = &self.siblings, .next = &self.siblings};
        self.next = null;
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
        const tmp = task_struct.init(virt, uid, gid, tp);
        self.pid = tmp.pid;
        self.regs.esp = task_stack_top;
        self.virtual_space = tmp.virtual_space;
        self.state = tmp.state;
        self.uid = tmp.uid;
        self.gid = tmp.gid;
        self.pid = pid;
        pid += 1;
        self.next = null;
        self.stack_bottom = stack_bottom;
        var cursor: *task_struct = current;
        tasks_mutex.lock();
        while (cursor.next != null) {
            cursor = cursor.next.?;
        }
        cursor.next = self;

        // tree logic
        self.siblings = .{.prev = &self.siblings, .next = &self.siblings};
        self.children = .{.prev = &self.children, .next = &self.children};
        current.add_child(self);
        tasks_mutex.unlock();
    }

    pub fn add_child(parent: *task_struct, child: *task_struct) void {
        if (parent.children.next.? != &parent.children) {
            lst.list_add(&child.siblings, parent.children.next.?);
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

        if (self.siblings.next.? != &self.siblings) {
            parent.children.next = self.siblings.next;
            parent.children.prev = self.siblings.prev;
            const prev_sibling: *lst.list_head = self.siblings.prev.?;
            const next_sibling: *lst.list_head = self.siblings.next.?;
            prev_sibling.next = next_sibling;
            next_sibling.prev = prev_sibling;
        } else {
            parent.children.next = &parent.children;
            parent.children.prev = &parent.children;
            // if we are child of initial_task we already removed ourselfs from the list
        }

        if (self.children.next.? != &self.children) {
            const first_child: *lst.list_head = self.children.next.?;
            const first_child_next: *lst.list_head = self.children.next.?.next.?;
            var cursor: *lst.list_head = first_child;
            var task: *task_struct = undefined;

            while (cursor.next.? != first_child) {
               task = lst.container_of(task_struct, @intFromPtr(cursor), "siblings");
               task.state = .ZOMBIE; 
               cursor = cursor.next.?;
            }
            task = lst.container_of(task_struct, @intFromPtr(cursor), "siblings");
            task.state = .ZOMBIE;
            // initial task
            
            if (initial_task.children.next.? == &initial_task.children) {
                initial_task.children.next = first_child;
                initial_task.children.prev = first_child;
            } else {
                const child: *lst.list_head = initial_task.children.next.?;
                const child_prev: *lst.list_head = initial_task.children.next.?.prev.?;
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
