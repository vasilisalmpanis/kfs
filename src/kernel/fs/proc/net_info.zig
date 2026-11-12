const generic_ops = @import("generic_ops.zig");
const interface = @import("interface.zig");
const kernel = @import("../../main.zig");
const std = @import("std");

const Slice = struct {
    ptr: *anyopaque,
    len: u32,
};

fn dev_open(base: *kernel.fs.File, inode: *kernel.fs.Inode) anyerror!void {
    _ = inode;
    const dev_header =
        \\Inter-|   Receive                                                |  Transmit
        \\ face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
        \\
    ;
    const dev_format = "{s}: {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d}\n";

    kernel.net.dev.dev_mutex.lock();
    defer kernel.net.dev.dev_mutex.unlock();

    const head_opt = kernel.net.dev.dev_list;
    if (head_opt == null)
        return;

    const head = head_opt.?;

    var size: usize = dev_header.len;
    {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const net_dev = node.curr.entry(
                kernel.net.dev.NetDevice, "list"
            );
            size += std.fmt.count(
                dev_format,
                .{
                    std.mem.sliceTo(&net_dev.name, 0),
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                 },
            );
        }
    }

    const buffer = kernel.mm.kmallocSlice(u8, size) orelse
        return kernel.errors.PosixError.ENOMEM;
    errdefer kernel.mm.kfree(buffer.ptr);

    var offset: usize = 0;
    {
        const header_written = try std.fmt.bufPrint(
            buffer[offset..],
            dev_header,
            .{},
        );
        offset += header_written.len;

        var it = head.list.iterator();
        while (it.next()) |node| {
            const net_dev = node.curr.entry(
                kernel.net.dev.NetDevice, "list"
            );

            const written = try std.fmt.bufPrint(
                buffer[offset..],
                dev_format,
                .{
                    std.mem.sliceTo(&net_dev.name, 0),
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                 },
            );
            offset += written.len;
        }
    }

    try generic_ops.assignSlice(base, buffer);
}

const dev_file_ops = kernel.fs.FileOps{
    .open = dev_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

fn route_open(base: *kernel.fs.File, inode: *kernel.fs.Inode) anyerror!void {
    _ = inode;
    const route_header =
        "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n";
    const route_format = "{s}\t{X:0>8}\t{X:0>8}\t{X:0>4}\t0\t0\t0\t{X:0>8}\t0\t0\t0\n";

    kernel.net.ipv4.route.routes_lock.lock();
    defer kernel.net.ipv4.route.routes_lock.unlock();

    const head_opt = kernel.net.ipv4.route.routes;

    var size: usize = route_header.len;
    if (head_opt) |head| {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const rt = node.curr.entry(kernel.net.ipv4.route.Route, "list");
            size += std.fmt.count(
                route_format,
                .{
                    std.mem.sliceTo(&rt.dev.name, 0),
                    rt.dst, 0, rt.flags, rt.mask
                },
            );
        }
    }

    const buffer = kernel.mm.kmallocSlice(u8, size) orelse
        return kernel.errors.PosixError.ENOMEM;
    errdefer kernel.mm.kfree(buffer.ptr);

    var offset: usize = 0;
    @memcpy(buffer[0..route_header.len], route_header);
    offset += route_header.len;
    if (head_opt) |head| {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const rt = node.curr.entry(kernel.net.ipv4.route.Route, "list");
            const written = try std.fmt.bufPrint(
                buffer[offset..],
                route_format,
                .{
                    std.mem.sliceTo(&rt.dev.name, 0),
                    rt.dst, 0, rt.flags, rt.mask
                },
            );
            offset += written.len;
        }
    }

    try generic_ops.assignSlice(base, buffer);
}

const route_file_ops = kernel.fs.FileOps{
    .open = route_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

pub fn init() !void {
    const parent = try kernel.fs.procfs.mkdir(
        kernel.fs.procfs.root,
        "net"
    );
    const mode = kernel.fs.UMode.regular();
    _ = try interface.createFile(parent,
        "dev",
        &dev_file_ops,
        mode
    );
    _ = try interface.createFile(parent,
        "route",
        &route_file_ops,
        mode
    );
}
