const tsk = @import("kernel").task;
const printf = @import("./printf.zig").printf;

pub fn ps() void {
    var buf: ?*tsk.task_struct = &tsk.initial_task;
    while (buf) |curr| : (buf = buf.?.next) {
        printf("{d}: {any}\n", .{curr.pid, curr.state});
    }
}
