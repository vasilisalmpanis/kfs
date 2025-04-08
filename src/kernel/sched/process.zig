const tsk = @import("./task.zig");

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
