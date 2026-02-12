const arch = @import("arch");
const krn = @import("../main.zig");
const kthread = @import("../sched/kthread.zig");
const errors = @import("error-codes.zig").PosixError;

pub const CloneFlags = packed struct(u32) {
    sigmask:         u8 = 0,         // 0x00000000 - 0x000000ff: signal mask to be sent at exit
    VM:              bool = false,   // 0x00000100: Share virtual memory
    FS:              bool = false,   // 0x00000200: Share filesystem info
    FILES:           bool = false,   // 0x00000400: Share file descriptors
    SIGHAND:         bool = false,   // 0x00000800: Share signal handlers
    PIDFD:           bool = false,   // 0x00001000: Share pidfd
    PTRACE:          bool = false,   // 0x00002000: Continue tracing child
    VFORK:           bool = false,   // 0x00004000: Parent sleeps until child exits/execs
    PARENT:          bool = false,   // 0x00008000: Use same parent as cloner
    THREAD:          bool = false,   // 0x00010000: Same thread group
    NEWNS:           bool = false,   // 0x00020000: New mount namespace
    SYSVSEM:         bool = false,   // 0x00040000: Share SysV semaphore undo
    SETTLS:          bool = false,   // 0x00080000: Set TLS for child
    PARENT_SETTID:   bool = false,   // 0x00100000: Set parent TID in parent
    CHILD_CLEARTID:  bool = false,   // 0x00200000: Clear child TID on exit
    DETACHED:        bool = false,   // 0x00400000: Unused, ignored
    UNTRACED:        bool = false,   // 0x00800000: Cannot force CLONE_PTRACE
    CHILD_SETTID:    bool = false,   // 0x01000000: Set child TID in child
    NEWCGROUP:       bool = false,   // 0x02000000: New cgroup namespace
    NEWUTS:          bool = false,   // 0x04000000: New UTS namespace
    NEWIPC:          bool = false,   // 0x08000000: New IPC namespace
    NEWUSER:         bool = false,   // 0x10000000: New user namespace
    NEWPID:          bool = false,   // 0x20000000: New PID namespace
    NEWNET:          bool = false,   // 0x40000000: New network namespace
    IO:              bool = false,   // 0x80000000: Share I/O context

    const supported = CloneFlags{
        .sigmask = 0xff,
        .VM = true,
        .VFORK = true,
        .SETTLS = true,
    };

    pub fn isSupported(self: CloneFlags) bool {
        return @as(u32, @bitCast(self)) & ~@as(u32, @bitCast(supported)) == 0;
    }
};

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
    flags: CloneFlags,
    child_stack: u32,
    parent_tid: ?*u32,
    tls: u32,
    child_tid: ?*u32,
) !u32 {
    krn.logger.WARN(
        \\ clone:
        \\   child_stack: 0x{x:0>8}
        \\   parent_tid:  0x{x:0>8}
        \\   tls:         0x{x:0>8}
        \\   child_tld:   0x{x:0>8}
        \\   flags:       {any}
        , .{
            child_stack,
            @intFromPtr(parent_tid),
            tls,
            @intFromPtr(child_tid),
            flags,
        }
    );
    if (!flags.isSupported()) {
        krn.logger.WARN("clone: unsupported flags", .{});
        return errors.EINVAL;
    }
    if (flags.NEWNS and flags.FS)
        return errors.EINVAL;
    if (flags.NEWUSER and flags.FS)
        return errors.EINVAL;
    if (flags.THREAD and !flags.SIGHAND)
        return errors.EINVAL;
    if (flags.SIGHAND and !flags.VM)
        return errors.EINVAL;
    if (flags.PIDFD and flags.DETACHED)
        return errors.EINVAL;

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

    // TODO: implement refcount for MM struct and uncomment this.
    // if (flags.VM) {
    //     child.mm = krn.task.current.mm;
    // } else {
        child.mm = krn.task.current.mm.?.dup() orelse {
            krn.logger.ERROR("clone: failed to dup mm", .{});
            return errors.ENOMEM;
        };
    // }
    // errdefer if (!flags.VM) {
        errdefer if (child.mm) |mm|
            mm.delete();
    // };

    if (flags.FS) {
        child.fs = krn.task.current.fs;
    } else {
        child.fs = krn.task.current.fs.clone() catch {
            krn.logger.ERROR("clone: failed to clone fs", .{});
            return errors.ENOMEM;
        };
    }
    errdefer if (!flags.FS) child.fs.deinit();

    if (flags.FILES) {
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
    errdefer if (!flags.FILES) krn.mm.kfree(child.files);

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

    if (flags.SETTLS) {
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

    if (flags.PARENT_SETTID) {
        if (parent_tid) |ptid| {
            ptid.* = child.pid;
        }
    }

    if (flags.CHILD_SETTID) {
        if (child_tid) |ctid| {
            ctid.* = child.pid;
        }
    }

    try krn.fs.procfs.newProcess(child);
    return @intCast(child.pid);
}

pub fn vfork() !u32 {
    return clone(.{ .VFORK = true, .VM = true }, 0, null, 0, null);
}
