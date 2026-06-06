const kernel = @import("../main.zig");

pub const ThreadData = struct {
    nr_threads:     usize = 0,
    threads:        kernel.list.ListHead,
    ref:            kernel.RefCount,
    lock:           kernel.Spinlock,
    pending:        kernel.signals.SigPending,
    group_exit:     bool = false,
    group_exit_code: i32 = 0,

    fn setup(self: *ThreadData) void {
        self.nr_threads = 0;
        self.threads.setup();
        self.ref = kernel.RefCount.init();
        self.ref.get();
        self.ref.dropFn = delete;
        self.lock = kernel.Spinlock.init();
        self.pending = kernel.signals.SigPending.init();
        self.group_exit = false;
        self.group_exit_code = 0;
    }

    fn delete(ref: *kernel.RefCount) void {
        const data: *ThreadData = @fieldParentPtr("ref", ref);
        kernel.mm.kfree(data);
    }

    pub fn new() ?*ThreadData {
        if (kernel.mm.kmalloc(ThreadData)) |data| {
            data.setup();
            return data;
        }
        return null;
    }

    pub fn addNode(self: *ThreadData, task: *kernel.task.Task) void {
        const lock_state = self.lock.lock_irq_disable();
        self.threads.addTail(&task.thread_node);
        self.nr_threads += 1;
        self.lock.unlock_irq_enable(lock_state);
    }

    pub fn findThread(self: *ThreadData, tid: u32) ?*kernel.task.Task {
        const lock_state = self.lock.lock_irq_disable();
        defer self.lock.unlock_irq_enable(lock_state);

        var it = self.threads.iterator();
        if (it.next() == null)
            return null;
        var prev = &self.threads;
        while (it.next()) |i| {
            if (prev == i.curr)
                break ;
            prev = i.curr;
            const thread = i.curr.entry(kernel.task.Task, "thread_node");
            if (thread.pid == tid) {
                return thread;
            }
        }
        return null;
    }
};
