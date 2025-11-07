const interface = @import("interface.zig");
const kernel = @import("../../main.zig");
const inode = @import("inode.zig");
const std = @import("std");

// Create file for new task (used in doFork())
pub fn newProcess(task: *kernel.task.Task) !void {
    var buff: [5]u8 = .{0} ** 5;
    const slice = try std.fmt.bufPrint(buff[0..5], "{d}", .{task.pid});
    const parent = try kernel.fs.procfs.mkdir(kernel.fs.procfs.root, slice);
    const mode = kernel.fs.UMode{
        .usr = 4,
        .grp = 4,
        .other = 4,
        .type = kernel.fs.S_IFREG,
    };

    const stat_dentry = try interface.createFile(parent,
        "stat",
        &stat_file_ops,
        mode
    );
    const stat_inode: *inode.ProcInode = stat_dentry.inode.getImpl(inode.ProcInode, "base");
    stat_inode.task = task;

    const cmdline_dentry = try interface.createFile(parent,
        "cmdline",
        &cmdline_file_ops,
        mode
    );
    const cmdline_inode = cmdline_dentry.inode.getImpl(inode.ProcInode, "base");
    cmdline_inode.task = task;
}


pub fn deleteProcess(task: *kernel.task.Task) void {
    var buff: [5]u8 = .{0} ** 5;
    const slice = std.fmt.bufPrint(buff[0..5], "{d}", .{task.pid}) catch { return; };
    const dentry = kernel.fs.procfs.root.inode.ops.lookup(kernel.fs.procfs.root, slice) catch {
        @panic("Not found? This shouldn't happen\n");
    };
    _ = interface.deleteRecursive(dentry) catch {};

}


fn open(_: *kernel.fs.File, base: *kernel.fs.Inode) !void {
    const proc_inode = base.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        return kernel.errors.PosixError.EINVAL;
    };
    task.refcount.ref();
}

fn close(file: *kernel.fs.File) void {
    const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        @panic("Should not happen");
    };
    task.refcount.unref();
}

fn write(_: *kernel.fs.File, _: [*]const u8, _: u32) !u32 {
    return kernel.errors.PosixError.ENOSYS;
}

// /proc/stat file

fn stat_read(file: *kernel.fs.File, buff: [*]u8, size: u32) !u32 {
    const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        @panic("Should not happen");
    };
    var buffer: [256]u8 = .{0} ** 256;
    const string = try std.fmt.bufPrint(buffer[0..256],
        "{d} ({s}) S 2 0 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 14 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0",
        .{
            task.pid,
            std.mem.span(@as([*:0]u8, @ptrCast(&task.name))),
        }
    );
    kernel.logger.INFO("slice {s} len {d}\n", .{string, string.len});
    var to_read: u32 = size;
    if (file.pos >= string.len)
        return 0;
    if (file.pos + to_read >= string.len)
        to_read = string.len - file.pos;
    @memcpy(buff[0..to_read], string[file.pos..file.pos + to_read]);
    file.pos += to_read;
    return to_read;
}


pub const stat_file_ops = kernel.fs.FileOps{
    .open = open,
    .read = stat_read,
    .write = write,
    .close = close,
};

fn cmdline_read(file: *kernel.fs.File, buff: [*]u8, size: u32) !u32 {
    const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse {
        @panic("Should not happen");
    };
    const mm = task.mm orelse
        return 0;
    const args = try mm.accessTaskVM(mm.arg_start, mm.arg_end - mm.arg_start);
    defer kernel.mm.kfree(args.ptr);

    var written: usize = 0;
    var args_off: usize = 0;
    while (args_off < args.len) {
        const arg_ptr: [*:0]const u8 = @ptrCast(&args.ptr[args_off]);
        const arg: []const u8 = std.mem.span(arg_ptr);
        if (args_off + arg.len > file.pos) {
            const arg_pos = file.pos - args_off;
            var to_write = args_off + arg.len - file.pos;
            if (written + to_write > size)
                to_write = size - written;
            @memcpy(
                buff[written..written + to_write],
                arg[arg_pos..arg_pos + to_write]
            );
            written += to_write;
            file.pos += to_write;
            if (written >= size)
                return written;
        }
        file.pos += 1;
        args_off += arg.len + 1;
    }
    return written;
}

pub const cmdline_file_ops = kernel.fs.FileOps{
    .open = open,
    .read = cmdline_read,
    .write = write,
    .close = close,
};
