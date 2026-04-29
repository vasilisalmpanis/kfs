const krn = @import("../main.zig");
const tsk = krn.task;
const errors = krn.errors.PosixError;
const std = @import("std");

pub fn getPID() !u32 {
    return @intCast(tsk.current.pid);
}

pub fn getPPID() !u32 {
    var pid: u16 = 0;
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
    return @intCast(tsk.current.gid);
}

pub fn setGID(gid: u16) !u32 {
    // TODO implement correctly
    tsk.current.gid = gid;
    return 0;
}

pub fn getPGID(pid: i32) !u32 {
    if (pid < 0)
        return errors.EEXIST;
    if (pid == 0)
        return tsk.current.pgid;
    if (tsk.current.findByPid(@intCast(pid))) |task| {
        defer task.refcount.put();
        return task.pgid;
    }
    return errors.ESRCH;
}

pub fn getPGRP() !u32 {
    return tsk.current.pgid;
}

pub fn getSID(pid: i32) !u32 {
    if (pid < 0)
        return errors.EINVAL;
    if (pid == 0)
        return tsk.current.sid;
    if (tsk.current.findByPid(@intCast(pid))) |task| {
        defer task.refcount.put();
        return task.sid;
    }
    return errors.ESRCH;
}

pub fn setSID() !u32 {
    if (tsk.current.pgid == tsk.current.pid)
        return errors.EPERM;
    tsk.current.sid = tsk.current.pid;
    tsk.current.pgid = tsk.current.pid;
    tsk.current.clearControllingTTY();
    return tsk.current.sid;
}

pub fn setPGID(pid: i32, pgid: i32) !u32 {
    krn.logger.INFO("setPGID pid: {d}, pgid: {d}", .{pid, pgid});
    if (pgid < 0)
        return errors.EINVAL;
    if (pid < 0)
        return errors.ESRCH;
    var _task: ?*tsk.Task = null;
    if (pid == 0) {
        _task = tsk.current;
    } else if (tsk.current.findByPid(@intCast(pid))) |task| {
        defer task.refcount.put();
        _task = task;
    }
    if (_task) |t| {
        if (pgid == 0) {
            t.pgid = t.pid;
        } else {
            t.pgid = @intCast(pgid);
        }
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

pub fn getEGID32() !u32 {
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

pub fn setgroups32(size: u32, list: ?[*]const u32) !u32 {
    if (tsk.current.uid != 0)
        return errors.EPERM;
    const groups_size: usize = size;
    if (groups_size > tsk.MAX_GROUPS)
        return errors.EINVAL;
    if (groups_size == 0) {
        tsk.current.groups_count = 0;
        return 0;
    }
    const user_list = list orelse
        return errors.EFAULT;
    var idx: usize = 0;
    while (idx < groups_size) : (idx += 1) {
        tsk.current.groups[idx] = @intCast(user_list[idx]);
    }
    tsk.current.groups_count = @intCast(groups_size);
    return 0;
}

pub fn getgroups32(size: u32, list: ?[*]u32) !u32 {
    const groups_count: usize = tsk.current.groups_count;
    if (size == 0)
        return @intCast(groups_count);
    if (@as(usize, size) < groups_count)
        return errors.EINVAL;
    const user_list = list orelse
        return errors.EFAULT;
    var idx: usize = 0;
    while (idx < groups_count) : (idx += 1) {
        user_list[idx] = tsk.current.groups[idx];
    }
    return @intCast(groups_count);
}

pub fn setgroups(size: u32, list: ?[*]const u16) !u32 {
    if (tsk.current.uid != 0)
        return errors.EPERM;
    if (size == 0)
        return setgroups32(0, null);
    const user_list = list orelse
        return errors.EFAULT;
    var groups32: [tsk.MAX_GROUPS]u32 = .{0} ** tsk.MAX_GROUPS;
    const groups_size: usize = size;
    if (groups_size > tsk.MAX_GROUPS)
        return errors.EINVAL;
    var idx: usize = 0;
    while (idx < groups_size) : (idx += 1) {
        groups32[idx] = user_list[idx];
    }
    return setgroups32(size, groups32[0..].ptr);
}

pub fn getgroups(size: u32, list: ?[*]u16) !u32 {
    const groups_count: usize = tsk.current.groups_count;
    if (size == 0)
        return @intCast(groups_count);
    if (@as(usize, size) < groups_count)
        return errors.EINVAL;
    const user_list = list orelse
        return errors.EFAULT;
    var idx: usize = 0;
    while (idx < groups_count) : (idx += 1) {
        user_list[idx] = tsk.current.groups[idx];
    }
    return @intCast(groups_count);
}
