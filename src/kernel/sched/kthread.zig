const km = @import("../mm/kmalloc.zig");
const tsk = @import("./task.zig");
const printf = @import("debug").printf;
const mm = @import("../mm/init.zig");
const arch = @import("arch");
const krn = @import("../main.zig");
const std = @import("std");


const PAGE_SIZE = @import("arch").PAGE_SIZE;
pub const STACK_PAGES = 3;
pub const STACK_SIZE: u32 = (STACK_PAGES - 1) * PAGE_SIZE;

pub const ThreadHandler = *const fn (arg: ?*const anyopaque) i32;

fn threadWrapper() callconv(.c) noreturn {
    tsk.current.refcount.ref();
    tsk.current.result = tsk.current.threadfn.?(tsk.current.arg);
    tsk.current.finish();
    while (true) {}
}

pub fn kthreadStackAlloc(num_of_pages: u32) u32 {
    const stack: u32 = mm.virt_memory_manager.findFreeSpace(
        num_of_pages,
        mm.PAGE_OFFSET,
        0xFFFFF000,
        false
    );
    for (0..num_of_pages) |index| {
        const page: u32 = mm.virt_memory_manager.pmm.allocPage();
        if (page == 0) {
            for (0..index) |idx| {
                mm.virt_memory_manager.unmapPage(stack + idx * PAGE_SIZE, true);
            }
            return 0;
        }
        mm.virt_memory_manager.mapPage(stack + index * PAGE_SIZE,
            page,
            .{.writable = index != 0}
        );
    }
    return stack + PAGE_SIZE;
}

pub fn kthreadStackFree(addr: u32) void {
    var page: u32 = addr - PAGE_SIZE; // RO page
    mm.virt_memory_manager.unmapPage(page, true);
    page += PAGE_SIZE;
    mm.virt_memory_manager.unmapPage(page, true);
    page += PAGE_SIZE;
    mm.virt_memory_manager.unmapPage(page, true);
    page += PAGE_SIZE;
}

pub fn kthreadCreate(f: ThreadHandler, arg: ?*const anyopaque, name: [*:0]const u8) !*tsk.Task {
    var stack: u32 = undefined;
    const new_task: ?*tsk.Task = km.kmalloc(tsk.Task);
    if (new_task) |task| {
        stack = kthreadStackAlloc(STACK_PAGES);
        if (stack == 0) {
            km.kfree(task);
            return error.MemoryAllocation;
        }
        const stack_top: u32 = arch.setupStack(
            stack + STACK_SIZE,
            @intFromPtr(&threadWrapper),
            0,
            arch.idt.KERNEL_CODE_SEGMENT,
            arch.idt.KERNEL_DATA_SEGMENT,
        );
        task.threadfn = f;
        task.arg = arg;
        task.mm = &mm.proc_mm.init_mm;
        task.fs = krn.task.initial_task.fs;
        task.initSelf(
            stack_top,
            stack,
            0,
            0,
            1,
            .KTHREAD,
            std.mem.span(name)
        ) catch |err| {
            krn.mm.kfree(task);
            return err;
        };
        return task;
    } else {
        return error.MemoryAllocation;
    }
}

pub fn kthreadStop(thread: *tsk.Task) i32 {
    thread.refcount.ref();
    thread.should_stop = true;
    while (thread.state != .STOPPED) {}
    const result = thread.result;
    thread.refcount.unref();
    return result;
}
