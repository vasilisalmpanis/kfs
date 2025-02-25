const vmm = @import("arch").vmm;
const lst = @import("../utils/list.zig");
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
pub const task_struct = packed struct {
    pid:            u32,
    stack_top:      u32,
    virtual_space:  u32,
    state:          task_state,
    parent:         *task_struct,
    children:       lst.list_head,
    siblings:       lst.list_head,
    signals:        [10]u8,
    uid:            u16,
    gid:            u16,

    pub fn init(virt: u32, uid: u16, gid: u16) task_struct {
        return task_struct{
            .pid = 0,
            .stack_top = stack_top,
            .virtual_space = virt,
            .state = task_state.STOPPED,
            .children = .{
                .next = @This(),
                .prev = @This(),
            },
            .siblings = .{
                .next = @This(),
                .prev = @This(),
            },
            .parent = @This(),
            .signals = .{0} ** 10,
            .uid = uid,
            .gid = gid,
        };
    }

    pub fn init_self(self: *task_struct, virt: u32, uid: u16, gid: u16) void {
        const tmp = self.init(virt, uid, gid);
        self.pid = tmp.pid;
        self.stack_top = tmp.stack_top;
        self.virtual_space = tmp.virtual_space;
        self.state = tmp.state;
        self.parent = tmp.parent;
        self.children = tmp.children;
        self.siblings = tmp.siblings;
        self.signals = tmp.signals;
        self.uid = tmp.uid;
        self.gid = tmp.gid;
    }
};

extern const stack_top: u32;

const initial_task = task_struct.init(
    vmm.initial_page_dir,
    0,  // uid
    0   // gid
);


pub var current = &initial_task;
