const krn = @import("../main.zig");
const errors = @import("./error-codes.zig").PosixError;

pub const Sysinfo = extern struct {
    uptime:     i32 = 0,
    loads:      [3]u32 = .{ 0, 0, 0 },
    totalram:   u32 = 0,
    freeram:    u32 = 0,
    sharedram:  u32 = 0,
    bufferram:  u32 = 0,
    totalswap:  u32 = 0,
    freeswap:   u32 = 0,
    procs:      u16 = 0,
    pad:        u16 = 0,
    totalhigh:  u32 = 0,
    freehigh:   u32 = 0,
    mem_unit:   u32 = 1,
    _padding:   [8]u8 = .{0} ** 8,
};

fn countTasks() u16 {
    var count: u16 = 0;
    const lock_state = krn.task.tasks_lock.lock_irq_disable();
    defer krn.task.tasks_lock.unlock_irq_enable(lock_state);

    var it = krn.task.initial_task.list.iterator();
    while (it.next()) |i| {
        const curr = i.curr.entry(krn.task.Task, "list");
        if (curr.state != .STOPPED and curr.state != .ZOMBIE)
            count += 1;

    }
    return count;
}

pub fn sysinfo(info: ?*Sysinfo) !u32 {
    const sinfo = info
        orelse return errors.EFAULT;

    sinfo.uptime = @intCast(krn.jiffies.getSecondsFromStart());
    sinfo.loads = .{ 0, 0, 0 };

    const total_ram: u32 = @truncate(krn.mm.mem_size);
    sinfo.totalram = total_ram;
    sinfo.freeram = total_ram / 2;
    sinfo.sharedram = 0;
    sinfo.bufferram = 0;

    sinfo.totalswap = 0;
    sinfo.freeswap = 0;

    sinfo.procs = countTasks();

    sinfo.totalhigh = 0;
    sinfo.freehigh = 0;

    // 1 = bytes
    sinfo.mem_unit = 1;
    return 0;
}
