const tsk = @import("kernel").task;
const printf_len = @import("./printf.zig").printf_len;
const printf = @import("./printf.zig").printf;

pub fn ps() void {
    var it = tsk.initial_task.list.iterator();
    while (it.next()) |i| {
        const task = i.curr.entry(tsk.task_struct, "list");
        printf("{d}: {any}\n", .{task.pid, task.state});
    }
    printf("stopped tasks {any}\n", .{tsk.stopped_tasks});
}

pub fn ps_tree(task: *tsk.task_struct, level: u32, last_child: bool) void {
    const len = printf_len("{d} ", .{task.pid});
    if (!task.children.is_single()) {
        var it = task.children.next.?.iterator();
        while (it.next()) |i| {
            ps_tree(
                i.curr.entry(tsk.task_struct, "siblings"),
                level + len,
                i.is_last()
            );
        }
    }
    if (!last_child) {
        printf("\n", .{});
        for (0..level) |_| {
            printf(" ", .{});
        }
    }
}

