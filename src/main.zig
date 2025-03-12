const TTY = @import("drivers").tty.TTY;
const keyboard = @import("drivers").keyboard;
const PIT = @import("drivers").pit.PIT;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const screen = @import("drivers").screen;
const dbg = @import("debug");
const builtin = @import("std").builtin;
const idt = @import("arch").idt;
const Serial = @import("drivers").Serial;
const Logger = @import("debug").Logger;
pub const mm = @import("kernel").mm;
pub const vmm = @import("arch").vmm;
pub const irq = @import("kernel").irq;
const krn = @import("kernel");
const syscalls = @import("kernel").syscalls;

extern const stack_top: u32;


pub fn panic(
    msg: []const u8,
    stack: ?*builtin.StackTrace,
    first_trace_addr: ?usize
) noreturn {
    dbg.printf(
        "\nPANIC: {s}\nfirst_trace_addr {?}\nstack: {?}\n",
        .{msg, first_trace_addr, stack}
    );
    dbg.TraceStackTrace(20);
    system.halt();
    while (true) {}
}

pub fn tty_thread(_: ?*const anyopaque) i32 {
    while (krn.task.current.should_stop != true) {
        if (keyboard.keyboard.get_input()) |input| {
            screen.current_tty.?.input(input);
        }
    }
    return 0;
}

fn test_thread(arg: ?*const anyopaque) i32 {
    var res: i32 = 0;
    while (!krn.task.current.should_stop) {
        const cnt: *i32 = @ptrCast(@constCast(@alignCast(arg)));
        res *= cnt.*;
        // if (cnt.* == 5)
        //     krn.logger.DEBUG("thread: {any}\n", .{cnt.*});
    }
    return res;
}

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    krn.serial = Serial.init();
    krn.logger = Logger.init(.DEBUG);

    const boot_info: *multiboot.multiboot_info = @ptrFromInt(address);
    krn.logger.INFO("Boot info {}", .{boot_info});

    gdt.gdt_init();
    krn.logger.INFO("GDT initialized", .{});

    mm.mm_init(boot_info);
    krn.logger.INFO("Memory initialized", .{});

    var scrn: screen.Screen = screen.Screen.init(boot_info);
    screen.current_tty = &scrn.tty[0];
    krn.pit = PIT.init(1000);
    idt.idt_init();
    krn.logger.INFO("IDT initialized", .{});
    
    irq.register_handler(1, &keyboard.keyboard_interrupt);
    krn.logger.INFO("Keyboard handler added", .{});
    krn.task.initial_task.setup(@intFromPtr(&vmm.initial_page_dir), @intFromPtr(&stack_top));
    irq.register_handler(0, &krn.timer_handler);
    syscalls.initSyscalls();
    _ = krn.kthread_create(&tty_thread, null) catch null;
    krn.logger.INFO("TTY thread started", .{});

    const arg1: u32 = 1;
    _ = krn.kthread_create(&test_thread, &arg1) catch null;
    const arg2: u32 = 2;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    const arg3: u32 = 3;
    _ = krn.kthread_create(&test_thread, &arg3) catch null;
    const arg4: u32 = 4;
    _ = krn.kthread_create(&test_thread, &arg4) catch null;
    const arg5: u32 = 5;
    _ = krn.kthread_create(&test_thread, &arg5) catch null;
    const arg11: u32 = 11;
    _ = krn.kthread_create(&test_thread, &arg11) catch null;
    const arg12: u32 = 12;
    _ = krn.kthread_create(&test_thread, &arg12) catch null;
    const arg13: u32 = 13;
    _ = krn.kthread_create(&test_thread, &arg13) catch null;
    const arg14: u32 = 14;
    _ = krn.kthread_create(&test_thread, &arg14) catch null;
    const arg15: u32 = 15;
    _ = krn.kthread_create(&test_thread, &arg15) catch null;
    while (true) {
        asm volatile ("hlt");
    }
    panic("You shouldn't be here");
}
