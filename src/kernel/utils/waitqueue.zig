const krn = @import("../main.zig");
const lst = @import("./list.zig");
const arch = @import("arch");

pub const WaitQueueNode = struct {
    task: *krn.task.Task,
    list: lst.ListHead,
    wake_fn: ?*const fn(*WaitQueueNode) void,

    pub fn init(task: *krn.task.Task) WaitQueueNode {
        return WaitQueueNode{
            .task = task,
            .list = lst.ListHead.init(),
            .wake_fn = WaitQueueNode.cleanupInWake,
        };
    }

    pub fn setup(self: *WaitQueueNode) void {
        self.list.setup();
    }

    fn cleanupInWake(self: *WaitQueueNode) void {
        self.list.del();
        self.list.setup();
    }
};

pub const WaitQueueHead = struct {
    list: lst.ListHead,
    lock: krn.Spinlock,

    pub fn init() WaitQueueHead {
        return WaitQueueHead{
            .list = lst.ListHead.init(),
            .lock = krn.Spinlock.init(),
        };
    }

    pub fn setup(self: *WaitQueueHead) void {
        self.lock = krn.Spinlock.init();
        self.list.setup();
    }

    pub fn isSetup(self: *WaitQueueHead) bool {
        return self.list.next != null;
    }

    pub fn wait(
        self: *WaitQueueHead,
        interruptable: bool,
        timeout: u32
    ) void {
        const tsk = krn.task.current;
        var node = WaitQueueNode.init(tsk);
        node.setup();
        const lock_state = self.lock.lock_irq_disable();
        self.list.addTail(&node.list);

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
        self.lock.unlock_irq_enable(lock_state);

        krn.sched.reschedule();

    }

    pub fn addToQueue(
        self: *WaitQueueHead,
        node: *WaitQueueNode,
    ) void{
        const lock_state = self.lock.lock_irq_disable();

        self.list.addTail(&node.list);

        self.lock.unlock_irq_enable(lock_state);
    }

    pub fn waitIfInQueue(
        self: *WaitQueueHead,
        node: *WaitQueueNode,
        interruptable: bool,
        timeout: u32
    ) void{
        const lock_state = self.lock.lock_irq_disable();
        if (node.list.isEmpty()) {
            self.lock.unlock_irq_enable(lock_state);
            return;
        }

        if (timeout != 0) {
            node.task.wakeup_time = krn.currentMs() + timeout;
        } else {
            node.task.wakeup_time = 0;
        }
        if (interruptable) {
            node.task.state = .INTERRUPTIBLE_SLEEP;
        } else {
            node.task.state = .UNINTERRUPTIBLE_SLEEP;
        }
        self.lock.unlock_irq_enable(lock_state);

        krn.sched.reschedule();
    }

    pub fn wakeUpOne(self: *WaitQueueHead) void {
        const lock_state = self.lock.lock_irq_disable();
        defer self.lock.unlock_irq_enable(lock_state);

        if (self.list.isEmpty())
            return;
        const first_node = self.list.next.?.entry(WaitQueueNode, "list");
        if (first_node.wake_fn) |_fn| _fn(first_node);
        if (first_node.task.state != .STOPPED and first_node.task.state != .ZOMBIE)
            first_node.task.state = .RUNNING;
    }

    pub fn wakeUpAll(self: *WaitQueueHead) void {
        const lock_state = self.lock.lock_irq_disable();
        defer self.lock.unlock_irq_enable(lock_state);

        while (!self.list.isEmpty()) {
            const curr_node = self.list.next.?.entry(WaitQueueNode, "list");
            if (curr_node.wake_fn) |_fn| _fn(curr_node);
            curr_node.list.setup();
            if (curr_node.task.state != .STOPPED and curr_node.task.state != .ZOMBIE)
                curr_node.task.state = .RUNNING;
        }
    }

    pub fn removeNode(self: *WaitQueueHead, node: *WaitQueueNode) void {
        const lock_state = self.lock.lock_irq_disable();
        defer self.lock.unlock_irq_enable(lock_state);

        node.list.del();
        node.list.setup();
    }
};
