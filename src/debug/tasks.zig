const tsk = @import("kernel").task;
const lst = @import("kernel").list;
const printf = @import("./printf.zig").printf;

pub fn ps() void {
    var buf: ?*tsk.task_struct = &tsk.initial_task;
    while (buf) |curr| : (buf = buf.?.next) {
        printf("{d}: {any}\n", .{curr.pid, curr.state});
    }
}
pub fn ps_tree(task: *tsk.task_struct) void {
    printf("{d}\n", .{task.pid});
    if (task.children.next != &task.children) {
        const child: *tsk.task_struct = lst.list_entry(tsk.task_struct, @intFromPtr(task.children.next), "siblings");
        if (child == &tsk.initial_task)
            return ;
        ps_tree(child);
        var sibling = child.siblings.next;
        while (sibling != &child.siblings) : (sibling = sibling.?.next) {
            const buf = lst.list_entry(tsk.task_struct, @intFromPtr(sibling), "siblings");
            ps_tree(buf);
        }
    }
}
