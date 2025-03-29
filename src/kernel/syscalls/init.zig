const register = @import("../irq/syscalls.zig").registerSyscall;

pub fn init() void {
    register(62, &@import("./kill.zig").kill);
}
