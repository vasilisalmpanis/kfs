const register = @import("../irq/syscalls.zig").registerSyscall;

pub fn init() void {
    register(57, &@import("./fork.zig").fork);
    register(39, &@import("../sched/process.zig").getPID);
    register(62, &@import("./kill.zig").kill);
    register(110, &@import("../sched/process.zig").getPPID);
}
