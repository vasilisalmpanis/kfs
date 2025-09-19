const tsk = @import("../sched/task.zig");
const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

pub fn time(t: u32, _: u32, _: u32, _: u32, _: u32, _: u32) !u32 {
    const current_time: u32 = 0; // TODO: Implement proper time tracking
    
    if (t != 0) {
        const time_ptr: *u32 = @ptrFromInt(t);
        time_ptr.* = current_time;
    }
    
    return current_time;
}
