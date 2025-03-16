const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const printf = @import("debug").printf;
const vmm = @import("arch").vmm;
const mm_init = @import("../mm/init.zig");
const regs = @import("arch").regs;


const PAGE_SIZE = @import("arch").PAGE_SIZE;
const STACK_PAGES = 3;
const STACK_SIZE: u32 = (STACK_PAGES - 1) * PAGE_SIZE;

const ThreadHandler = *const fn (arg: ?*const anyopaque) i32;

fn thread_wrapper() noreturn {
    tsk.current.result = tsk.current.threadfn.?(tsk.current.arg);
    tsk.current.state = .STOPPED;
    while (true) {}
}

pub fn setup_stack(stack_top: u32) u32 {
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
    stack_ptr[9] = 0;               // edx
    stack_ptr[10] = 0;              // ecx
    stack_ptr[11] = 0;              // eax
    stack_ptr[12] = 0;              // int code
    stack_ptr[13] = 0;              // error code
    stack_ptr[14] = @intFromPtr(&thread_wrapper); // eip
    stack_ptr[15] = 0x8;            // cs
    stack_ptr[16] = 0x202;          // eflags
    stack_ptr[17] = 0x0;            // useresp
    stack_ptr[18] = 0x10;           // ss
    return @intFromPtr(stack_ptr);
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
    const stack_top: u32 = setup_stack(
        stack + STACK_SIZE,
    );
    new_task.threadfn = f;
    new_task.arg = arg;
    new_task.init_self(
        @intFromPtr(&vmm.initial_page_dir),
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

