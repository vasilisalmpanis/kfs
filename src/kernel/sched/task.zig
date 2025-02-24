const vmm = @import("arch").vmm;
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
    children:       ?*task_struct,
    next:           ?*task_struct,
    parent:         ?*task_struct,
    signals:        [10]u8,
    uid:            u16,
    gid:            u16,

    pub fn init(virt: u32, uid: u16, gid: u16) task_struct {
        return task_struct{
            .pid = 0,
            .stack_top = stack_top,
            .virtual_space = virt,
            .state = task_state.STOPPED,
            .children = null,
            .next = null,
            .parent = null,
            .signals = .{0} ** 10,
            .uid = uid,
            .gid = gid,
        };
    }
};

extern const stack_top: u32;

const initial_task = task_struct.init(
    vmm.initial_page_dir,
    0,  // uid
    0   // gid
);
