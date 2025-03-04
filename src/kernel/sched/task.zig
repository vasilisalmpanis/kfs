const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");

var pid: u32 = 0;

const task_state = enum(u8) {
    RUNNING,
    UNINTERRUPTIBLE_SLEEP,
    INTERRUPTIBLE_SLEEP,
    STOPPED,
    ZOMBIE,
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

pub const task_struct align(8) = struct {
    pid:            u32,
    stack_top:      u32,
    virtual_space:  u32,
    parent:         ?*task_struct,
    children:       lst.list_head,
    siblings:       lst.list_head,
    // signals:        [8]u8,
    uid:            u16,
    gid:            u16,
    tss:            tss_struct,
    f:              u32,
    state:          task_state,

    pub fn init(virt: u32, task_stack_top: u32, uid: u16, gid: u16) task_struct {
        return task_struct{
            .pid = 0,
            .stack_top = task_stack_top,
            .virtual_space = virt,
            .state = task_state.STOPPED,
            .children = .{
                .next = null,
                .prev = null,
            },
            .siblings = .{
                .next = null,
                .prev = null,
            },
            .parent = null,
            // .signals = .{0} ** 10,
            .uid = uid,
            .gid = gid,
            .tss = tss_struct.init(),
            .f   = 0,
        };
    }

    pub fn setup(self: *task_struct, virt: u32, task_stack_top: u32) void {
        self.siblings.next = &self.siblings;
        self.siblings.prev = &self.siblings;
        self.children.next = &self.children;
        self.children.prev = &self.children;
        self.parent = self;
        self.stack_top = task_stack_top;
        self.virtual_space = virt;
        self.pid = pid;
        pid += 1;
    }

    pub fn init_self(self: *task_struct, virt: u32, task_stack_top: u32, uid: u16, gid: u16) void {
        const tmp = task_struct.init(virt, task_stack_top, uid, gid);
        self.pid = tmp.pid;
        self.stack_top = tmp.stack_top;
        self.virtual_space = tmp.virtual_space;
        self.state = tmp.state;
        self.siblings.next = &self.siblings;
        self.siblings.prev = &self.siblings;
        self.children.next = &self.children;
        self.children.prev = &self.children;
        self.parent = self;
        // self.signals = tmp.signals;
        self.uid = tmp.uid;
        self.gid = tmp.gid;
        self.pid = pid;
        pid += 1;
    }
};

// const initial_task = task_struct.init(
//     @as(u32, @intFromPtr(vmm.initial_page_dir)),
//     0,  // uid
//     0   // gid
// );
//
pub var initial_task = task_struct.init(0, 0, 0, 0);
pub var current = &initial_task;
