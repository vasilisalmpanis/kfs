const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const lst = @import("../utils/list.zig");
const printf = @import("debug").printf;

pub fn kthread_create(f: *const anyopaque) u32 {
    const addr = km.kmalloc(@sizeOf(tsk.task_struct));
    if (addr == 0)
        return 0;
    const new_task: *tsk.task_struct = @ptrFromInt(
        addr
    );
    new_task.init_self(0, 0, 0); // To implement
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
