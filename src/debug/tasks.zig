const tsk = @import("kernel").task;
const lst = @import("kernel").list;
const printf = @import("./printf.zig").printf;

pub fn ps() void {
    var buf: *lst.list_head = &tsk.initial_task.next;
    while (buf.next != &tsk.initial_task.next) : (buf = buf.next.?) {
        const task: *tsk.task_struct = lst.list_entry(tsk.task_struct, @intFromPtr(buf), "next");
        printf("{d}: {any}\n", .{task.pid, task.state});
    }
    const task: *tsk.task_struct = lst.list_entry(tsk.task_struct, @intFromPtr(buf), "next");
    printf("{d}: {any}\n", .{task.pid, task.state});
    printf("stopped tasks {any}\n", .{tsk.stopped_tasks});
}

pub fn ps_tree(task: *tsk.task_struct, level: u32) void {
    for (0..level) |_| {
        printf(" ", .{});
    }
    printf("{d}\n", .{task.pid});
    if (task.children.next != &task.children) {
        const child: *tsk.task_struct = lst.list_entry(tsk.task_struct, @intFromPtr(task.children.next), "siblings");
        if (child == &tsk.initial_task)
            return ;
        ps_tree(child, level + 1);
        var sibling = child.siblings.next;
        while (sibling != &child.siblings) : (sibling = sibling.?.next) {
            const buf = lst.list_entry(tsk.task_struct, @intFromPtr(sibling), "siblings");
            ps_tree(buf, level + 1);
        }
    }
}
