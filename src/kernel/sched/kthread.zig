const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const lst = @import("../utils/list.zig");
const printf = @import("debug").printf;
const vmm = @import("arch").vmm;

const STACK_SIZE: u32 = 4096 * 2;

pub fn setup_stack(stack_top: u32, f: *const anyopaque) void {
    var stack_ptr: [*]u32 = @ptrFromInt(stack_top);
    stack_ptr -= 1;
    stack_ptr[0] = @intFromPtr(f);
    stack_ptr -= 1;
    stack_ptr[0] = 0;
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
    new_task.init_self(@intFromPtr(&vmm.initial_page_dir), stack + STACK_SIZE - 8, 0, 0); // TODO: change this something more clear
    new_task.tss.eip = @intFromPtr(f);
    setup_stack(stack + STACK_SIZE, f);
    new_task.parent = tsk.current;
    if (tsk.current.children.next == &tsk.current.children) {
        tsk.current.children.next = &new_task.siblings;
    } else {
        if (tsk.current.children.next == null) {
            km.kfree(addr);
            return 0;
        }
        lst.list_add_tail(
            &new_task.siblings,
            tsk.current.children.next.?
        );
    }
    new_task.f = @intFromPtr(f);
    return new_task.pid;
    // return 0;
}
