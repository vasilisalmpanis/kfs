const tsk = @import("./task.zig");
const mm = @import("../mm/init.zig");
const km = @import("../mm/kmalloc.zig");
const errors = @import("../syscalls/error-codes.zig").PosixError;
const kthread = @import("./kthread.zig");
const arch = @import("arch");
const fs = @import("../fs/fs.zig");
const krn = @import("../main.zig");
const procfs =krn.fs.procfs;

pub fn doFork() !u32 {
    var child: *tsk.Task = km.kmalloc(tsk.Task) orelse {
        krn.logger.ERROR("fork: failed to alloc child task", .{});
        return errors.ENOMEM;
    };
    errdefer km.kfree(child);
    const stack: u32 = kthread.kthreadStackAlloc(kthread.STACK_PAGES);
    if (stack == 0) {
        krn.logger.ERROR("fork: failed to alloc kthread stack", .{});
        return errors.ENOMEM;
    }
    errdefer kthread.kthreadStackFree(stack);
    child.mm = tsk.current.mm.?.dup() orelse {
        krn.logger.ERROR("fork: failed to dup mm", .{});
        return errors.ENOMEM;
    };
    errdefer km.kfree(child.mm.?); // BUG: free mappings and then mm
    child.fs = tsk.current.fs.clone() catch {
        krn.logger.ERROR("fork: failed to clone fs", .{});
        return errors.ENOMEM;
    };
    errdefer child.fs.deinit();
    if (fs.TaskFiles.new()) |files| {
        errdefer km.kfree(files);
        child.files = files;
        child.files.dup(tsk.current.files) catch {
            // TODO: free mm and free fs.
            krn.logger.ERROR("fork: failed to clone files", .{});
            return errors.ENOMEM;
        };
    } else {
            krn.logger.ERROR("fork: failed to clone files", .{});
            return errors.ENOMEM;
    }
    errdefer km.kfree(child.files);

    const stack_top = stack + kthread.STACK_SIZE - @sizeOf(arch.Regs);
    const parent_regs: *arch.Regs = @ptrFromInt(arch.gdt.tss.esp0 - @sizeOf(arch.Regs));
    var child_regs: *arch.Regs = @ptrFromInt(stack_top);
    child_regs.* = parent_regs.*;
    child_regs.eax = 0;
    child.tls = krn.task.current.tls;
    child.limit = krn.task.current.limit;
    child.initSelf(
        stack_top,
        stack,
        tsk.current.uid,
        tsk.current.gid,
        tsk.current.pgid,
        .PROCESS,
        tsk.current.name[0..16]
    ) catch |err| {
        // TODO: understand when error comes from kmalloc allocation of files
        // or from resizing of fds/map inside files to do deinit
        krn.logger.ERROR("fork: failed to init child task: {any}", .{err});
        return errors.ENOMEM;
    };
    try procfs.newProcess(child);
    return @intCast(child.pid);
}

pub fn getPID() !u32 {
    return @intCast(tsk.current.pid);
}

pub fn getPPID() !u32 {
    var pid: u32 = 0;
    if (tsk.current.tree.parent != null) {
        const p: *tsk.Task = tsk.current.tree.parent.?.entry(tsk.Task, "tree");
        pid = p.pid;
    }
    return @intCast(pid);
}

pub fn getUID() !u32 {
    return tsk.current.uid;
}

pub fn setUID(uid: u16) !u32 {
    // TODO implement correctly
    tsk.current.uid = uid;
    return 0;
}

pub fn getGID() !u32 {
    return tsk.current.gid;
}

pub fn setGID(gid: u16) !u32 {
    // TODO implement correctly
    tsk.current.gid = gid;
    return 0;
}

pub fn getPGID(pid_arg: u32) !u32 {
    const pid: i32 = @intCast(pid_arg);
    if (pid < 0)
        return errors.EEXIST;
    if (pid == 0)
        return tsk.current.pgid;
    if (tsk.current.findByPid(pid_arg)) |task| {
        defer task.refcount.unref();
        return task.pgid;
    }
    return errors.ESRCH;
}

pub fn setPGID(pid_arg: u32, pgid_arg: u32) !u32 {
    const pid: i32 = @intCast(pid_arg);
    const pgid: i32 = @intCast(pgid_arg);
    if (pid < 0) {
        return errors.ESRCH;
    } else if (pid == 0) {
        tsk.current.pgid = @intCast(pgid_arg);
        return 0;
    }
    if (tsk.current.findByPid(pid_arg)) |task| {
        defer task.refcount.unref();
        task.pgid = @intCast(pgid);
        return 0;
    }
    return errors.ESRCH;
}
