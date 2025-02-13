const register_handler = @import("./manage.zig").register_handler;

pub fn syscallsManager() void {

}

pub fn registerSyscalls() void {
    register_handler(0x80, &syscallsManager);
}