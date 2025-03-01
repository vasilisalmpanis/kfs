const tsk = @import("./task.zig");
const dbg = @import("debug");
const lst = @import("../utils/list.zig");

fn switch_to(task: *tsk.task_struct) void {
    _ = task;
}

pub fn timer_handler() void {
    dbg.printf("timer\n", .{});
    if (tsk.current.children.next) |curr_ptr| {
        const addr: u32 = @intFromPtr(curr_ptr);
        const curr = lst.container_of(
            tsk.task_struct,
            addr,
            "siblings"
        );
        if (true or false) {
            if (curr.siblings.next) |next_ptr| {
                const addr_next: u32 = @intFromPtr(next_ptr);
                const next = lst.container_of(
                    tsk.task_struct,
                    addr_next,
                    "siblings"
                );
                switch_to(next);
            }
        }
    }
}
