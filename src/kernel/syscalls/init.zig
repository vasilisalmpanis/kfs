const register = @import("../irq/syscalls.zig").registerSyscall;

pub fn init() void {
    register(57, &@import("./fork.zig").fork);
    register(39, &@import("../sched/process.zig").getPID);
    register(62, &@import("./kill.zig").kill);
    register(102, &@import("../sched/process.zig").getUID);
    register(104, &@import("../sched/process.zig").getGID);
    register(105, &@import("../sched/process.zig").setUID);
    register(106, &@import("../sched/process.zig").setGID);
    register(110, &@import("../sched/process.zig").getPPID);
}
