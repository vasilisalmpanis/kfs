const krn = @import("../main.zig");
const tsk = krn.task;
const errors = krn.errors.PosixError;

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
    krn.logger.INFO("setPGID pid: {d}, pgid: {d}", .{pid, pgid});
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

pub fn getEUID() !u32 {
    return krn.task.current.uid;
}

pub fn getEUID32() !u32 {
    return krn.task.current.uid;
}

pub fn getEGID() !u32 {
    return krn.task.current.gid;
}

pub fn getresuid() !u32 {
    return krn.task.current.uid;
}

pub fn setresuid() !u32 {
    return 0;
}

pub fn getresgid() !u32 {
    return krn.task.current.gid;
}

pub fn setresgid() !u32 {
    return 0;
}
