const register = @import("../irq/syscalls.zig").registerSyscall;

pub fn init() void {
    register(1, &@import("./exit.zig").exit);
    register(2, &@import("./fork.zig").fork);
    register(4, &@import("./write.zig").write);
    register(37, &@import("./kill.zig").kill);
    register(20, &@import("../sched/process.zig").getPID);
    register(23, &@import("../sched/process.zig").setUID);
    register(24, &@import("../sched/process.zig").getUID);
    register(46, &@import("../sched/process.zig").setGID);
    register(47, &@import("../sched/process.zig").getGID);
    register(57, &@import("../sched/process.zig").setPGID);
    register(64, &@import("../sched/process.zig").getPPID);
    register(114, &@import("./wait.zig").wait4);
    register(132, &@import("../sched/process.zig").getPGID);
}
