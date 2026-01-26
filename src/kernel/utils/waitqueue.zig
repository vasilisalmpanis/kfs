const krn = @import("../main.zig");
const lst = @import("./list.zig");

const WaitQueueNode = struct {
    task: *krn.task.Task,
    list: lst.ListHead,

    pub fn init(task: *krn.task.Task) WaitQueueNode {
        return WaitQueueNode{
            .task = task,
            .list = lst.ListHead.init(),
        };
    }

    pub fn setup(self: *WaitQueueNode) void {
        self.list.setup();
    }
};

pub const WaitQueueHead = struct {
    list: lst.ListHead,
    lock: krn.Mutex,

    pub fn init() WaitQueueHead {
        return WaitQueueHead{
            .list = lst.ListHead.init(),
            .lock = krn.Mutex.init(),
        };
    }

    pub fn setup(self: *WaitQueueHead) void {
        self.lock = krn.Mutex.init();
        self.list.setup();
    }

    pub fn wait(
        self: *WaitQueueHead,
        interruptable: bool,
        timeout: u32
    ) void {
        const tsk = krn.task.current;
        var node = WaitQueueNode.init(tsk);
        node.setup();
        self.lock.lock();
        self.list.addTail(&node.list);
        self.lock.unlock();

        if (timeout != 0) {
            tsk.wakeup_time = krn.currentMs() + timeout;
        } else {
            tsk.wakeup_time = 0;
        }
        if (interruptable) {
            tsk.state = .INTERRUPTIBLE_SLEEP;
        } else {
            tsk.state = .UNINTERRUPTIBLE_SLEEP;
        }
        krn.sched.reschedule();
    }

    pub fn wakeUpOne(self: *WaitQueueHead) void {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.list.isEmpty())
            return;
        const first_node = self.list.next.?.entry(WaitQueueNode, "list");
        self.list.next.?.del();
        first_node.task.state = .RUNNING;
    }

    pub fn wakeUpAll(self: *WaitQueueHead) void {
        self.lock.lock();
        defer self.lock.unlock();

        while (!self.list.isEmpty()) {
            const curr_node = self.list.next.?.entry(WaitQueueNode, "list");
            self.list.next.?.del();
            curr_node.task.state = .RUNNING;
        }
    }
};
