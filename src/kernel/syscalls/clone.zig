const arch = @import("arch");
const krn = @import("../main.zig");
const kthread = @import("../sched/kthread.zig");
const errors = @import("error-codes.zig").PosixError;

pub const CLONE_VM:             u32 = 0x00000100; // Share virtual memory
pub const CLONE_FS:             u32 = 0x00000200; // Share filesystem info
pub const CLONE_FILES:          u32 = 0x00000400; // Share file descriptors
pub const CLONE_SIGHAND:        u32 = 0x00000800; // Share signal handlers
pub const CLONE_PTRACE:         u32 = 0x00002000; // Continue tracing child
pub const CLONE_VFORK:          u32 = 0x00004000; // Parent sleeps until child exits/execs
pub const CLONE_PARENT:         u32 = 0x00008000; // Use same parent as cloner
pub const CLONE_THREAD:         u32 = 0x00010000; // Same thread group
pub const CLONE_NEWNS:          u32 = 0x00020000; // New mount namespace
pub const CLONE_SYSVSEM:        u32 = 0x00040000; // Share SysV semaphore undo
pub const CLONE_SETTLS:         u32 = 0x00080000; // Set TLS for child
pub const CLONE_PARENT_SETTID:  u32 = 0x00100000; // Set parent TID in parent
pub const CLONE_CHILD_CLEARTID: u32 = 0x00200000; // Clear child TID on exit
pub const CLONE_DETACHED:       u32 = 0x00400000; // Unused, ignored
pub const CLONE_UNTRACED:       u32 = 0x00800000; // Cannot force CLONE_PTRACE
pub const CLONE_CHILD_SETTID:   u32 = 0x01000000; // Set child TID in child
pub const CLONE_NEWCGROUP:      u32 = 0x02000000; // New cgroup namespace
pub const CLONE_NEWUTS:         u32 = 0x04000000; // New UTS namespace
pub const CLONE_NEWIPC:         u32 = 0x08000000; // New IPC namespace
pub const CLONE_NEWUSER:        u32 = 0x10000000; // New user namespace
pub const CLONE_NEWPID:         u32 = 0x20000000; // New PID namespace
pub const CLONE_NEWNET:         u32 = 0x40000000; // New network namespace
pub const CLONE_IO:             u32 = 0x80000000; // Share I/O context

const UserDesc = extern struct {
    entry_number:       i32,
    base_addr:          u32,
    limit:              u32,
    seg_32bit:          u32,
    contents:           u32,
    read_exec_only:     u32,
    limit_in_pages:     u32,
    seg_not_present:    u32,
    useable:            u32,
};

pub fn clone(
    flags: u32,
    child_stack: u32,
    parent_tid: ?*u32,
    tls: u32,
    child_tid: ?*u32,
) !u32 {
    krn.logger.WARN(
        \\ clone:
        \\   flags:       0x{x:0>8}
        \\   child_stack: 0x{x:0>8}
        \\   parent_tid:  0x{x:0>8}
        \\   tls:         0x{x:0>8}
        \\   child_tld:   0x{x:0>8}
        , .{
            flags,
            child_stack,
            @intFromPtr(parent_tid),
            tls,
            @intFromPtr(child_tid)
        }
    );
    if ((flags & CLONE_THREAD != 0) and (flags & CLONE_SIGHAND == 0)) {
        return errors.EINVAL;
    }
    if ((flags & CLONE_SIGHAND != 0) and (flags & CLONE_VM == 0)) {
        return errors.EINVAL;
    }

    var child: *krn.task.Task = krn.mm.kmalloc(krn.task.Task) orelse {
        krn.logger.ERROR("clone: failed to alloc child task", .{});
        return errors.ENOMEM;
    };
    errdefer krn.mm.kfree(child);

    const stack: u32 = kthread.kthreadStackAlloc(kthread.STACK_PAGES);
    if (stack == 0) {
        krn.logger.ERROR("clone: failed to alloc kthread stack", .{});
        return errors.ENOMEM;
    }
    errdefer kthread.kthreadStackFree(stack);

    if (flags & CLONE_VM != 0) {
        child.mm = krn.task.current.mm;
    } else {
        child.mm = krn.task.current.mm.?.dup() orelse {
            krn.logger.ERROR("clone: failed to dup mm", .{});
            return errors.ENOMEM;
        };
    }
    errdefer if (flags & CLONE_VM == 0) {
        if (child.mm) |mm|
            krn.mm.kfree(mm);
    };

    if (flags & CLONE_FS != 0) {
        child.fs = krn.task.current.fs;
    } else {
        child.fs = krn.task.current.fs.clone() catch {
            krn.logger.ERROR("clone: failed to clone fs", .{});
            return errors.ENOMEM;
        };
    }
    errdefer if (flags & CLONE_FS == 0) child.fs.deinit();

    if (flags & CLONE_FILES != 0) {
        child.files = krn.task.current.files;
    } else {
        if (krn.fs.TaskFiles.new()) |files| {
            errdefer krn.mm.kfree(files);
            child.files = files;
            child.files.dup(krn.task.current.files) catch {
                krn.logger.ERROR("clone: failed to clone files", .{});
                return errors.ENOMEM;
            };
        } else {
            krn.logger.ERROR("clone: failed to alloc files", .{});
            return errors.ENOMEM;
        }
    }
    errdefer if (flags & CLONE_FILES == 0) krn.mm.kfree(child.files);

    child.fpu_used = krn.task.current.fpu_used;
    child.save_fpu_state = false;
    if (krn.task.current.fpu_used) {
        if (krn.task.current.save_fpu_state) {
            arch.fpu.saveFPUState(&krn.task.current.fpu_state);
            krn.task.current.save_fpu_state = false;
            arch.fpu.setTaskSwitched();
        }
        child.fpu_state = krn.task.current.fpu_state;
    }

    const stack_top = stack + kthread.STACK_SIZE - @sizeOf(arch.Regs);
    const parent_regs: *arch.Regs = @ptrFromInt(arch.gdt.tss.esp0 - @sizeOf(arch.Regs));
    var child_regs: *arch.Regs = @ptrFromInt(stack_top);
    child_regs.* = parent_regs.*;
    child_regs.eax = 0;

    if (child_stack != 0) {
        child_regs.useresp = child_stack;
    }

    if (flags & CLONE_SETTLS != 0) {
        const user_desc: *const UserDesc = @ptrFromInt(tls);
        child.tls = user_desc.base_addr;
        child.limit = if (user_desc.limit_in_pages != 0) user_desc.limit
            else 0xFFFFFFFF;
    } else {
        child.tls = krn.task.current.tls;
        child.limit = krn.task.current.limit;
    }

    child.initSelf(
        stack_top,
        stack,
        krn.task.current.uid,
        krn.task.current.gid,
        krn.task.current.pgid,
        .PROCESS,
        krn.task.current.name[0..16],
    ) catch |err| {
        krn.logger.ERROR("clone: failed to init child task: {t}", .{err});
        return errors.ENOMEM;
    };

    // krn.logger.WARN(
    //     \\ clone after initSelf:
    //     \\   stack:                 0x{x:0>8}
    //     \\   stack_top:             0x{x:0>8}
    //     \\   child.regs.esp:        0x{x:0>8}
    //     \\   child_regs.eip:        0x{x:0>8}
    //     \\   child.stack_bottom:    0x{x:0>8}
    //     \\
    //     , .{
    //         stack,
    //         stack_top,
    //         child.regs.getStackPointer(),
    //         child_regs.eip,
    //         child.stack_bottom,
    //     }
    // );

    if (flags & CLONE_PARENT_SETTID != 0) {
        if (parent_tid) |ptid| {
            ptid.* = child.pid;
        }
    }

    if (flags & CLONE_CHILD_SETTID != 0) {
        if (child_tid) |ctid| {
            ctid.* = child.pid;
        }
    }

    try krn.fs.procfs.newProcess(child);
    return @intCast(child.pid);
}
