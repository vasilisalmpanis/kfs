const krn = @import("../main.zig");
const lst = @import("./list.zig");
const arch = @import("arch");

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

    pub fn wait(
        self: *WaitQueueHead,
        interruptable: bool,
        timeout: u32
    ) void {
        const tsk = krn.task.current;
        var node = WaitQueueNode.init(tsk);
        node.setup();
        var lock_state = self.lock.lock_irq_disable();
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

        lock_state = self.lock.lock_irq_disable();
        if (!node.list.isEmpty()) {
            node.list.del();
        }
        self.lock.unlock_irq_enable(lock_state);
    }

    pub fn wakeUpOne(self: *WaitQueueHead) void {
        const lock_state = self.lock.lock_irq_disable();
        defer self.lock.unlock_irq_enable(lock_state);

        if (self.list.isEmpty())
            return;
        const first_node = self.list.next.?.entry(WaitQueueNode, "list");
        self.list.next.?.del();
        if (first_node.task.state != .STOPPED and first_node.task.state != .ZOMBIE)
            first_node.task.state = .RUNNING;
    }

    pub fn wakeUpAll(self: *WaitQueueHead) void {
        const lock_state = self.lock.lock_irq_disable();
        defer self.lock.unlock_irq_enable(lock_state);

        while (!self.list.isEmpty()) {
            const curr_node = self.list.next.?.entry(WaitQueueNode, "list");
            self.list.next.?.del();
            if (curr_node.task.state != .STOPPED and curr_node.task.state != .ZOMBIE)
                curr_node.task.state = .RUNNING;
        }
    }
};
