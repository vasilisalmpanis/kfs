const fmt = @import("std").fmt;
const krn = @import("kernel");
const printfLen = @import("./printf.zig").printfLen;
const writer = @import("./printf.zig").writer;

fn mountTreeHelper(mnt: *krn.fs.Mount, level: u32, last_child: bool) void {
    const len = printfLen("<{s}: {s}> ", .{mnt.root.name, mnt.sb.fs.name});
    if (mnt.tree.hasChildren()) {
        var it = mnt.tree.child.?.siblingsIterator();
        while (it.next()) |i| {
            mountTreeHelper(
                i.curr.entry(krn.fs.Mount, "tree"),
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

pub fn printMountTree() void {
    mountTreeHelper(krn.task.initial_task.fs.root.mnt, 0, false);
}
