const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const lst = @import("../utils/list.zig");

pub fn kthread_create(f: *anyopaque) u32 {
    var new_task: *tsk.task_struct = @ptrFromInt(
        km.kmalloc(@sizeOf(tsk.task_struct))
    );
    if (new_task.* == 0)
        return 0;
    new_task.init_self(0, 0, 0); // To implement
    new_task.parent = tsk.current;
    if (tsk.current.children.next == &tsk.current.children) {
        tsk.current.children.next = &new_task.siblings;
    } else {
        lst.list_add_tail(
            &new_task.siblings,
            &tsk.current.children.next
        );
    }
    _ = f;
    return new_task.pid;
}

