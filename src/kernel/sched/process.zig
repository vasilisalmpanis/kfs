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
    child.* = tsk.Task.init(0, 0, 0, .PROCESS);
    try child.assignPID();

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
    errdefer child.mm.?.delete();
    child.fs = tsk.current.fs.dup() catch {
        krn.logger.ERROR("fork: failed to clone fs", .{});
        return errors.ENOMEM;
    };
    errdefer child.fs.ref.put();

    child.files = try krn.task.current.files.dup();
    errdefer child.files.ref.put();

    const sighand = krn.task.current.sighand orelse
        @panic("No userspace task should have sighand == NULL\n");
    child.sighand = try sighand.dup();
    errdefer child.sighand.?.ref.put();

    var child_fpu_state: ?*arch.fpu.FPUState = null;
    var child_fpu_used = tsk.current.fpu_used;
    if (tsk.current.fpu_used and tsk.current.fpu_state != null) {
        if (tsk.current.save_fpu_state) {
            arch.fpu.saveFPUState(tsk.current.fpu_state.?);
            tsk.current.save_fpu_state = false;
            arch.fpu.setTaskSwitched();
        }
        child_fpu_state = km.kmalloc(arch.fpu.FPUState) orelse {
            krn.logger.ERROR("fork: failed to alloc child fpu state", .{});
            return errors.ENOMEM;
        };
        child_fpu_state.?.* = tsk.current.fpu_state.?.*;
    } else {
        child_fpu_used = false;
    }
    errdefer if (child_fpu_state) |state| km.kfree(state);

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
    errdefer procfs.deleteProcess(child);
    child.fpu_state = child_fpu_state;
    child.fpu_used = child_fpu_used;
    child.save_fpu_state = false;
    return @intCast(child.pid);
}
