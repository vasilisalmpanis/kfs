const krn = @import("../../main.zig");
const std = @import("std");
const drivers = @import("drivers");
const interface = @import("interface.zig");
const generic_ops = @import("generic_ops.zig");

const TaskCounters = struct {
    total: u32 = 0,
    running: u32 = 0,
    blocked: u32 = 0,
};

fn countTasks() TaskCounters {
    var counters = TaskCounters{};

    const lock_state = krn.task.tasks_lock.lock_irq_disable();
    defer krn.task.tasks_lock.unlock_irq_enable(lock_state);

    var it = krn.task.initial_task.list.iterator();
    while (it.next()) |node| {
        const task = node.curr.entry(krn.task.Task, "list");
        if (task.state == .STOPPED or task.state == .ZOMBIE)
            continue;

        counters.total += 1;
        switch (task.state) {
            .RUNNING => counters.running += 1,
            .UNINTERRUPTIBLE_SLEEP => counters.blocked += 1,
            else => {},
        }
    }

    return counters;
}

fn countFreePages() usize {
    const pmm = krn.mm.virt_memory_manager.pmm;
    if (pmm.free_area.len == 0)
        return 0;

    var free_pages: usize = 0;
    var idx: usize = 0;
    while (idx < pmm.free_area.len) {
        if (pmm.free_area[idx] != 0)
            free_pages += 1;
        idx += 1;
    }
    return free_pages;
}

fn meminfo_open(file: *krn.fs.File, _: *krn.fs.Inode) !void {
    const total_kb: usize = @intCast(krn.mm.mem_size / 1024);
    const free_kb: usize = (countFreePages() * krn.mm.PAGE_SIZE) / 1024;
    const avail_kb: usize = free_kb;

    const meminfo_format: []const u8 =
        \\MemTotal:       {d} kB
        \\MemFree:        {d} kB
        \\MemAvailable:   {d} kB
        \\Buffers:        0 kB
        \\Cached:         0 kB
        \\SwapCached:     0 kB
        \\Active:         0 kB
        \\Inactive:       0 kB
        \\SwapTotal:      0 kB
        \\SwapFree:       0 kB
        \\Shmem:          0 kB
        \\Slab:           0 kB
        \\
    ;
    const buff_size = std.fmt.count(meminfo_format, .{
        total_kb,
        free_kb,
        avail_kb,
    });

    const buff = krn.mm.kmallocSlice(u8, buff_size) orelse
        return krn.errors.PosixError.ENOMEM;
    errdefer krn.mm.kfree(buff.ptr);

    _ = try std.fmt.bufPrint(
        buff,
        meminfo_format,
        .{
            total_kb,
            free_kb,
            avail_kb,
        },
    );

    try generic_ops.assignSlice(file, buff);
}

fn stat_open(file: *krn.fs.File, _: *krn.fs.Inode) !void {
    const cpu_ticks = krn.jiffies.getCpuTicks();
    const counters = countTasks();
    const btime: u32 = 0;

    const stat_format: []const u8 =
        \\cpu  {d} 0 {d} {d} 0 0 0 0 0 0
        \\cpu0 {d} 0 {d} {d} 0 0 0 0 0 0
        \\intr 0
        \\ctxt 0
        \\btime {d}
        \\processes {d}
        \\procs_running {d}
        \\procs_blocked {d}
        \\
    ;

    const buff_size = std.fmt.count(
        stat_format,
        .{
            cpu_ticks.user,
            cpu_ticks.system,
            cpu_ticks.idle,
            cpu_ticks.user,
            cpu_ticks.system,
            cpu_ticks.idle,
            btime,
            counters.total,
            counters.running,
            counters.blocked,
        },
    );

    const buff = krn.mm.kmallocSlice(u8, buff_size) orelse
        return krn.errors.PosixError.ENOMEM;
    errdefer krn.mm.kfree(buff.ptr);

    _ = try std.fmt.bufPrint(
        buff,
        stat_format,
        .{
            cpu_ticks.user,
            cpu_ticks.system,
            cpu_ticks.idle,
            cpu_ticks.user,
            cpu_ticks.system,
            cpu_ticks.idle,
            btime,
            counters.total,
            counters.running,
            counters.blocked,
        },
    );

    try generic_ops.assignSlice(file, buff);
}

fn uptime_open(file: *krn.fs.File, _: *krn.fs.Inode) !void {
    const hz = drivers.pit.HZ;
    const ticks = krn.jiffies.jiffies;
    const secs = if (hz == 0) 0 else ticks / hz;
    const centis = if (hz == 0) 0 else ((ticks % hz) * 100) / hz;

    const buff_size = std.fmt.count(
        "{d}.{d:0>2} {d}.{d:0>2}\n",
        .{ secs, centis, secs, centis }
    );
    const buff = krn.mm.kmallocSlice(u8, buff_size) orelse
        return krn.errors.PosixError.ENOMEM;
    errdefer krn.mm.kfree(buff.ptr);

    _ = try std.fmt.bufPrint(
        buff,
        "{d}.{d:0>2} {d}.{d:0>2}\n",
        .{ secs, centis, secs, centis }
    );
    try generic_ops.assignSlice(file, buff);
}

fn loadavg_open(file: *krn.fs.File, _: *krn.fs.Inode) !void {
    const counters = countTasks();
    const runnable = counters.running;
    const total = counters.total;
    const last_pid = krn.task.current.pid;

    const buff_size = std.fmt.count("0.00 0.00 0.00 {d}/{d} {d}\n", .{
        runnable,
        total,
        last_pid,
    });
    const buff = krn.mm.kmallocSlice(u8, buff_size) orelse
        return krn.errors.PosixError.ENOMEM;
    errdefer krn.mm.kfree(buff.ptr);

    _ = try std.fmt.bufPrint(
        buff,
        "0.00 0.00 0.00 {d}/{d} {d}\n",
        .{
            runnable,
            total,
            last_pid,
        }
    );
    try generic_ops.assignSlice(file, buff);
}

const meminfo_ops = krn.fs.FileOps{
    .open = meminfo_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

const stat_ops = krn.fs.FileOps{
    .open = stat_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

const uptime_ops = krn.fs.FileOps{
    .open = uptime_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

const loadavg_ops = krn.fs.FileOps{
    .open = loadavg_open,
    .read = generic_ops.generic_read,
    .write = generic_ops.generic_write,
    .close = generic_ops.generic_close,
};

pub fn init() !void {
    const mode = krn.fs.UMode.regular();

    _ = try interface.createFile(krn.fs.procfs.root, "meminfo", &meminfo_ops, mode);
    _ = try interface.createFile(krn.fs.procfs.root, "stat", &stat_ops, mode);
    _ = try interface.createFile(krn.fs.procfs.root, "uptime", &uptime_ops, mode);
    _ = try interface.createFile(krn.fs.procfs.root, "loadavg", &loadavg_ops, mode);
}
