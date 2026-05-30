const kernel = @import("../main.zig");

pub const ThreadData = struct {
    nr_threads:     usize = 0,
    threads:        kernel.list.ListHead,
    ref:            kernel.RefCount,
    lock:           kernel.Spinlock,
    pending:        kernel.signals.SigPending,
    // TODO: Add locking

    fn setup(self: *ThreadData) void {
        self.nr_threads = 1;
        self.threads.setup();
        self.ref = kernel.RefCount.init();
        self.ref.get();
        self.ref.dropFn = delete;
        self.lock = kernel.Spinlock.init();
        self.pending = kernel.signals.SigPending.init();
    }

    fn delete(ref: *kernel.RefCount) void {
        const data: *ThreadData = @fieldParentPtr("ref", ref);
        kernel.task.current.thread_node.del();
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
        self.lock.unlock_irq_enable(lock_state);
    }
};

