const tsk = @import("./task.zig");
const mm = @import("../mm/init.zig");
const km = @import("../mm/kmalloc.zig");
const errors = @import("../syscalls/error-codes.zig");
const kthread = @import("./kthread.zig");
const arch = @import("arch");

pub fn doFork() i32 {
    var child: ?*tsk.Task = null;
    child = @ptrFromInt(km.kmalloc(@sizeOf(tsk.Task)));
    if (child == null) {
        return -errors.ENOMEM;
    }
    const stack: u32 = kthread.kthreadStackAlloc(kthread.STACK_PAGES);
    if (stack == 0) {
        km.kfree(@intFromPtr(child));
        return -errors.ENOMEM;
    }
    child.?.mm = tsk.current.mm.?.dup();
    if (child.?.mm == null) {
        km.kfree(stack);
        mm.kfree(@intFromPtr(child));
        return -errors.ENOMEM;
    }
    const stack_top = stack + kthread.STACK_SIZE - @sizeOf(arch.Regs);
    const parent_regs: *arch.Regs = @ptrFromInt(arch.gdt.tss.esp0 - @sizeOf(arch.Regs));
    var child_regs: *arch.Regs = @ptrFromInt(stack_top);
    child_regs.* = parent_regs.*;
    child_regs.eax = 0;
    child.?.initSelf(
        stack_top,
        stack,
        0, 
        0, 
        tsk.current.pgid,
        .PROCESS,
    );
    return @intCast(child.?.pid);
}

pub fn getPID() i32 {
    return @intCast(tsk.current.pid);
}

pub fn getPPID() i32 {
    var pid: u32 = 0;
    if (tsk.current.tree.parent != null) {
        const p: *tsk.Task = tsk.current.tree.parent.?.entry(tsk.Task, "tree");
        pid = p.pid;
    }
    return @intCast(pid);
}

pub fn getUID() i32 {
    return tsk.current.uid;
}

pub fn setUID(uid: u16) i32 {
    tsk.current.uid = uid;
    return 0;
}

pub fn getGID() i32 {
    return tsk.current.gid;
}

pub fn setGID(gid: u16) i32 {
    tsk.current.gid = gid;
    return 0;
}

pub fn getPGID(pid_arg: u32) i32 {
    const pid: i32 = @intCast(pid_arg);
    if (pid < 0)
        return -errors.EEXIST;
    if (pid == 0)
        return tsk.current.pgid;
    if (tsk.current.findByPid(pid_arg)) |task| {
        defer task.refcount.unref();
        return task.pgid;
    }
    return -errors.ESRCH;
}

pub fn setPGID(pid_arg: u32, pgid_arg: u32) i32 {
    const pid: i32 = @intCast(pid_arg);
    const pgid: i32 = @intCast(pgid_arg);
    if (pid < 0) {
        return -errors.ESRCH;
    } else if (pid == 0) {
        tsk.current.pgid = @intCast(pgid_arg);
        return 0;
    }
    if (tsk.current.findByPid(pid_arg)) |task| {
        defer task.refcount.unref();
        task.pgid = @intCast(pgid);
        return 0;
    }
    return -errors.ESRCH;
}
