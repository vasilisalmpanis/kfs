const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const printf = @import("debug").printf;
const mm_init = @import("../mm/init.zig");
const arch = @import("arch");
const lst = @import("../main.zig").list;


const PAGE_SIZE = @import("arch").PAGE_SIZE;
const STACK_PAGES = 3;
const STACK_SIZE: u32 = (STACK_PAGES - 1) * PAGE_SIZE;

const ThreadHandler = *const fn (arg: ?*const anyopaque) i32;

fn thread_wrapper() noreturn {
    tsk.current.result = tsk.current.threadfn.?(tsk.current.arg);
    tsk.tasks_mutex.lock();
    tsk.current.next.prev.?.next = tsk.current.next.next.?;
    tsk.current.next.next.?.prev = tsk.current.next.prev.?;
    if (tsk.stopped_tasks == null) {
       tsk.stopped_tasks = &tsk.current.next;
       tsk.stopped_tasks.?.next = tsk.stopped_tasks.?;
       tsk.stopped_tasks.?.prev = tsk.stopped_tasks.?;
    } else {
       lst.list_add_tail(&tsk.current.next, tsk.stopped_tasks.?);
    }
    tsk.current.state = .STOPPED;
    tsk.tasks_mutex.unlock();
    while (true) {}
}

pub fn kthread_stack_alloc(num_of_pages: u32) u32 {
    const stack: u32 = mm_init.virt_memory_manager.find_free_space(num_of_pages, 0xB0000000, 0xFFFFF000, false);
    for (0..num_of_pages) |index| {
        const page: u32 = mm_init.virt_memory_manager.pmm.alloc_page();
        if (page == 0) {
            for (0..index) |idx| {
                mm_init.virt_memory_manager.unmap_page(stack + idx * PAGE_SIZE);
            }
        }
        mm_init.virt_memory_manager.map_page(stack + index * PAGE_SIZE,
            page,
            .{.writable = index != 0}
        );
    }
    return stack + PAGE_SIZE;
}

pub fn kthread_free_stack(addr: u32) void {
    var page: u32 = addr - PAGE_SIZE; // RO page
    mm_init.virt_memory_manager.unmap_page(page);
    page += PAGE_SIZE;
    mm_init.virt_memory_manager.unmap_page(page);
    page += PAGE_SIZE;
    mm_init.virt_memory_manager.unmap_page(page);
    page += PAGE_SIZE;
}

pub fn kthread_create(f: ThreadHandler, arg: ?*const anyopaque) !*tsk.task_struct {
    const addr = km.kmalloc(@sizeOf(tsk.task_struct));
    var stack: u32 = undefined;
    if (addr == 0)
        return error.MemoryAllocation;
    const new_task: *tsk.task_struct = @ptrFromInt(
        addr
    );
    stack = kthread_stack_alloc(STACK_PAGES);
    if (stack == 0) {
        km.kfree(addr);
        return error.MemoryAllocation;
    }
    const stack_top: u32 = arch.setup_stack(
        stack + STACK_SIZE,
        @intFromPtr(&thread_wrapper)
    );
    new_task.threadfn = f;
    new_task.arg = arg;
    new_task.init_self(
        @intFromPtr(&arch.vmm.initial_page_dir),
        stack_top,
        stack,
        0,
        0,
        .KTHREAD
    );
    return new_task;
}

pub fn kthread_stop(thread: *tsk.task_struct) i32 {
    thread.refcount += 1;
    thread.should_stop = true;
    while (thread.state != .STOPPED) {
    }
    const result = thread.result;
    thread.refcount -= 1;
    return result;
}

