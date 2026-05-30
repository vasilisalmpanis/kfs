const kernel = @import("../main.zig");

pub const ThreadData = struct {
    nr_threads:     usize = 0,
    threads:        kernel.list.ListHead,
    ref:            kernel.RefCount,
    // TODO: Add locking

    fn setup(self: *ThreadData) void {
        self.nr_threads = 1;
        self.threads.setup();
        self.ref = kernel.RefCount.init();
        self.ref.get();
        self.ref.dropFn = delete;
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
        self.threads.addTail(&task.thread_node);
    }
};
