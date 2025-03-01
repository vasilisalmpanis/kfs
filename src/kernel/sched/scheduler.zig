const task = @import("./task.zig");
const dbg = @import("debug");
const lst = @import("../utils/list.zig");

fn switch_to(task: *task.task_struct) void {

}

pub fn timer_handler() void {
    dbg.printf("timer\n", .{});
    if (task.current.children.next) |curr_ptr| {
        const addr: u32 = @intFromPtr(curr_ptr);
        const curr = lst.container_of(
            task.task_struct,
            addr,
            "siblings"
        );
        if (true or false) {
            const addr_next: u32 = @intFromPtr(curr.siblings.next);
            const next = lst.container_of(
                task.task_struct,
                addr_next,
                "siblings"
            );
            switch_to(next);
        }
    }
}