const tsk = @import("./task.zig");
const mm = @import("../mm/init.zig");
const km = @import("../mm/kmalloc.zig");
const errors = @import("../syscalls/error-codes.zig");
const kthread = @import("./kthread.zig");
const arch = @import("arch");

pub fn doFork(state: *arch.Regs) i32 {
    var child: ?*tsk.Task = null;
    const page_directory: u32 = mm.virt_memory_manager.cloneVirtualSpace(); // it clones all memory including stack
    if (page_directory == 0)
        return -errors.ENOMEM;
    child = @ptrFromInt(km.kmalloc(@sizeOf(tsk.Task)));
    if (child == null) {
        // TODO: we need to free page directory
        return -errors.ENOMEM;
    }
    const stack: u32 = kthread.kthreadStackAlloc(kthread.STACK_PAGES);
    if (stack == 0) {
        // TODO: we need to free page directory
        km.kfree(@intFromPtr(child));
        return -errors.ENOMEM;
    }
    const stack_top: u32 = arch.setupStack(
        stack + kthread.STACK_SIZE,
        state.eip,
        state.useresp,
        arch.idt.USER_CODE_SEGMENT | 3,
        arch.idt.USER_DATA_SEGMENT | 3,
    );
    child.?.initSelf(
        page_directory,
        stack_top,
        stack,
        0, 
        0, 
        .PROCESS,
    );
    return @intCast(child.?.pid);
}
