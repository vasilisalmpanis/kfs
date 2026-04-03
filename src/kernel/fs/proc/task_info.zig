const dbg = @import("debug");
const generic_ops = @import("generic_ops.zig");
const interface = @import("interface.zig");
const kernel = @import("../../main.zig");
const inode = @import("inode.zig");
const arch = @import("arch");
const std = @import("std");

const kstack_snapshot_cap: usize = 4096;
const kstack_max_frames: u32 = 64;

// Create file for new task (used in doFork())
pub fn newProcess(task: *kernel.task.Task) !void {
    var buff: [5]u8 = .{0} ** 5;
    const slice = try std.fmt.bufPrint(buff[0..5], "{d}", .{task.pid});
    const parent = try kernel.fs.procfs.mkdir(kernel.fs.procfs.root, slice);
    const mode = kernel.fs.UMode.regular();

    const stat_dentry = try interface.createFile(parent,
        "stat",
        &stat_file_ops,
        mode
    );
    const stat_inode: *inode.ProcInode = stat_dentry.inode.getImpl(inode.ProcInode, "base");
    task.refcount.ref();
    stat_inode.task = task;

    const cmdline_dentry = try interface.createFile(parent,
        "cmdline",
        &cmdline_file_ops,
        mode
    );
    const cmdline_inode = cmdline_dentry.inode.getImpl(inode.ProcInode, "base");
    task.refcount.ref();
    cmdline_inode.task = task;

    const kstack_dentry = try interface.createFile(parent,
        "kernel_stack_trace",
        &kernel_stack_trace_file_ops,
        mode
    );
    const kstack_inode = kstack_dentry.inode.getImpl(inode.ProcInode, "base");
    task.refcount.ref();
    kstack_inode.task = task;
}


pub fn deleteProcess(task: *kernel.task.Task) void {
    var buff: [5]u8 = .{0} ** 5;
    const slice = std.fmt.bufPrint(buff[0..5], "{d}", .{task.pid}) catch {
        return;
    };
    const dentry = kernel.fs.procfs.root.inode.ops.lookup(kernel.fs.procfs.root, slice) catch {
        @panic("Not found? This shouldn't happen\n");
    };
    dentry.release();
    while (true) {
        _ = interface.deleteRecursive(dentry) catch |err| {
            kernel.logger.ERROR("deleting proc files {s} failed: {t}. ref: {d}", .{slice, err, dentry.ref.getValue()});
            continue ;
            // @panic("proc deleteRecursive");
        };
        break;
    }

}


fn open(_: *kernel.fs.File, _: *kernel.fs.Inode) !void {}

fn close(_: *kernel.fs.File) void {}

fn write(_: *kernel.fs.File, _: [*]const u8, _: usize) !usize {
    return kernel.errors.PosixError.ENOSYS;
}

fn parentPid(task: *kernel.task.Task) u32 {
    const lock_state = kernel.task.tasks_lock.lock_irq_disable();
    defer kernel.task.tasks_lock.unlock_irq_enable(lock_state);

    if (task.tree.parent) |parent_node| {
        const parent = parent_node.entry(kernel.task.Task, "tree");
        return parent.pid;
    }
    return 0;
}

// /proc/stat file

fn stat_read(file: *kernel.fs.File, buff: [*]u8, size: usize) !usize {
    const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse 
        return kernel.errors.PosixError.ESRCH;
    var buffer: [512]u8 = .{0} ** 512;
    kernel.logger.INFO("TASK name {s}\n", .{task.name[0..16]});
    const status: u8 = switch (task.state) {
        .RUNNING => 'R',
        .INTERRUPTIBLE_SLEEP => 'S',
        .UNINTERRUPTIBLE_SLEEP => 'D',
        .STOPPED => 'T',
        .ZOMBIE => 'Z',
    };
    const ppid = parentPid(task);
    const string = try std.fmt.bufPrint(buffer[0..512],
        "{d} ({s}) {c} {d} {d} 0 0 -1 0 0 0 0 0 {d} {d} 0 0 20 0 1 0 {d} 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0",
        .{
            task.pid,
            std.mem.span(@as([*:0]u8, @ptrCast(&task.name))),
            status,
            ppid,
            task.pgid,
            task.utime,
            task.stime,
            kernel.jiffies.jiffies,
        }
    );
    var to_read: usize = size;
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

fn cmdline_open(file: *kernel.fs.File, ino: *kernel.fs.Inode) !void {
    const proc_inode = ino.getImpl(inode.ProcInode, "base");
    const task = proc_inode.task orelse
        return kernel.errors.PosixError.ESRCH;
    file.data = null;
    const mm = task.mm orelse
        return;
    if (mm.arg_start == 0 or mm.arg_end <= mm.arg_start)
        return;
    const args = try mm.accessTaskVM(mm.arg_start, mm.arg_end - mm.arg_start);
    errdefer kernel.mm.kfree(args.ptr);

    try generic_ops.assignSlice(file, args);
}

pub const cmdline_file_ops = kernel.fs.FileOps{
    .open = cmdline_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

fn kernel_stack_trace_read(file: *kernel.fs.File, buff: [*]u8, size: usize) !usize {
    if (file.data == null) {
        const proc_inode = file.inode.getImpl(inode.ProcInode, "base");
        const task = proc_inode.task orelse
            return kernel.errors.PosixError.ESRCH;
        const kbuf = kernel.mm.kmallocSlice(u8, kstack_snapshot_cap) orelse
            return kernel.errors.PosixError.ENOMEM;
        errdefer kernel.mm.kfree(kbuf.ptr);

        arch.cpu.disableInterrupts();
        defer arch.cpu.enableInterrupts();
        const n = dbg.formatKernelStackTraceForTask(kbuf, kstack_max_frames, task);

        try generic_ops.assignSlice(file, kbuf[0..n]);
    }
    return generic_ops.generic_read(file, buff, size);
}

pub const kernel_stack_trace_file_ops = kernel.fs.FileOps{
    .open = open,
    .read = kernel_stack_trace_read,
    .write = write,
    .close = close,
};
