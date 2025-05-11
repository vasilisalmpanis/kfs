const tsk = @import("kernel").task;
const printfLen = @import("./printf.zig").printfLen;
const printf = @import("./printf.zig").printf;
const writer = @import("./printf.zig").writer;
const fmt = @import("std").fmt;
const krn = @import("kernel");
const arch = @import("arch");
const lookupSymbol = @import("./symbols.zig").lookupSymbol;
const std = @import("std");

fn printTask(task: *tsk.Task) void {
    var buffer: [10:0]u8 = .{'0', 'x' } ++ .{0} ** 8;
        const name: []const u8 = if (task.threadfn) |f| if_lbl: {
        break :if_lbl if (lookupSymbol(@intFromPtr(f))) |s| s else "";
    } else else_lbl: {
        _ = std.fmt.formatIntBuf(
            buffer[2..],
            task.regs.eip,
            16,
            .upper,
            .{.alignment = .right, .width = 8, .fill = '0' }
        );
        break :else_lbl &buffer;
    };
    printf("{d}: {s} {s} {s} {s} {d} | refs: {d}\n", .{
        task.pid,
        @tagName(task.state),
        @tagName(task.tsktype),
        if (task.regs.cs == arch.idt.KERNEL_CODE_SEGMENT) "KRN" else "USR",
        name,
        task.result,
        task.refcount.getValue(),
    });
}

pub fn ps() void {
    var it = tsk.initial_task.list.iterator();
    while (it.next()) |i| {
        printTask(i.curr.entry(tsk.Task, "list"));
    }
    if (tsk.stopped_tasks) |stopped| {
        printf("===STOPPED===\n", .{});
        it = stopped.iterator();
        while (it.next()) |i| {
            printTask(i.curr.entry(tsk.Task, "list"));
        }
    }
}

fn psTreeHelper(task: *tsk.Task, level: u32, last_child: bool) void {
    const len = printfLen("{d} ", .{task.pid});
    if (task.tree.hasChildren()) {
        var it = task.tree.child.?.siblingsIterator();
        while (it.next()) |i| {
            psTreeHelper(
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

pub fn psTree() void {
    psTreeHelper(&krn.task.initial_task, 0, false);
}
