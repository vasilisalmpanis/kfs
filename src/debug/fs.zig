const std = @import("std");
const fmt = @import("std").fmt;
const krn = @import("kernel");
const printf = @import("./printf.zig").printf;
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
        var buff: [20:0]u8 = .{0} ** 20;
        _ = std.fmt.printInt(
            &buff,
            0,
            10,
            .upper,
            .{ .alignment = .left, .fill = ' ', .width = level + 1 }
        );
        const slic: []u8 = std.mem.span(@as([*:0]u8, @ptrCast(&buff)));
        printf("\n{s}", .{slic[1..]});
    }
}

pub fn printMountTree() void {
    mountTreeHelper(krn.task.initial_task.fs.root.mnt, 0, false);
}
