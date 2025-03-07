const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const lst = @import("../utils/list.zig");
const printf = @import("debug").printf;
const vmm = @import("arch").vmm;
const regs = @import("arch").regs;

const STACK_SIZE: u32 = 4096 * 2;

pub fn setup_stack(stack_top: u32, f: *const anyopaque) u32 {
    var stack_ptr: [*]u32 = @ptrFromInt(stack_top - @sizeOf(regs));
    stack_ptr[0] = 0x10;
    stack_ptr[1] = 0x10;
    stack_ptr[2] = 0x10;
    stack_ptr[3] = 0x10;            // segments
    stack_ptr[4] = 0;               // GPR
    stack_ptr[5] = 0;
    stack_ptr[6] = 0;
    stack_ptr[7] = 0;
    stack_ptr[8] = 0;
    stack_ptr[9] = 0;
    stack_ptr[10] = 0;
    stack_ptr[11] = 0;
    stack_ptr[12] = 0;              // int code
    stack_ptr[13] = 0;              // error code
    stack_ptr[14] = @intFromPtr(f); // eip
    stack_ptr[15] = 0x8;            // cs
    stack_ptr[16] = 0x202;          // eflags
    stack_ptr[17] = 0x0;            // useresp
    stack_ptr[18] = 0x10;           // ss
    return @intFromPtr(stack_ptr);
}

pub fn kthread_create(f: *const anyopaque) u32 {
    const addr = km.kmalloc(@sizeOf(tsk.task_struct));
    var stack: u32 = undefined;
    if (addr == 0)
        return 0;
    const new_task: *tsk.task_struct = @ptrFromInt(
        addr
    );
    stack = km.kmalloc(STACK_SIZE);
    if (stack == 0) {
        km.kfree(addr);
        return 0;
    }
    const stack_top: u32 = setup_stack(stack + STACK_SIZE, f);
    new_task.init_self(
        @intFromPtr(&vmm.initial_page_dir),
        stack_top,
        0,
        0
    ); // TODO: change this something more clear
    return new_task.pid;
}
