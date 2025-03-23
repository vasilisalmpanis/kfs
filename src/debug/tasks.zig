const tsk = @import("kernel").task;
const printfLen = @import("./printf.zig").printfLen;
const printf = @import("./printf.zig").printf;
const writer = @import("./printf.zig").writer;
const fmt = @import("std").fmt;

pub fn ps() void {
    var it = tsk.initial_task.list.iterator();
    while (it.next()) |i| {
        const task = i.curr.entry(tsk.Task, "list");
        printf("{d}: {any}\n", .{task.pid, task.state});
    }
    printf("stopped tasks {any}\n", .{tsk.stopped_tasks});
}

pub fn psTree(task: *tsk.Task, level: u32, last_child: bool) void {
    const len = printfLen("{d} ", .{task.pid});
    if (task.tree.hasChildren()) {
        var it = task.tree.child.?.siblingsIterator();
        while (it.next()) |i| {
            psTree(
                i.curr.entry(tsk.Task, "tree"),
                level + len,
                i.isLast()
            );
        }
    }
    if (!last_child) {
        fmt.formatText(
            "\n",
            "s",
            .{
                .width = level + 1,
                .alignment = .left
            },
            writer
        ) catch {};
    }
}
