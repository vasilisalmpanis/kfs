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

var mtx = krn.Mutex.init();
var shared: u32 = 10;

fn test_thread(_: ?*const anyopaque) i32 {
    var i: u32 = 0;
    while (!krn.task.current.should_stop) {
        mtx.lock();
        var tmp: u32 = shared; // 10
        tmp += 1; // 11
        shared = tmp; // 11
        tmp = shared; // 11
        tmp -= 1; // 10
        shared = tmp; // 10
        mtx.unlock();
        i += 1;
        // krn.logger.INFO("remains: {d}\n", .{10000000 - i});
        if (i == 10000000)
            return 0;
    }
    return 0;
}

fn output_thread(_: ?*const anyopaque) i32 {
    while (!krn.task.current.should_stop) {
        krn.sleep(8000);
        mtx.lock();
        dbg.printf("shared: {d}\n", .{shared});
        mtx.unlock();
    }
    return 0;
}

var value: u32 = 0;

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    krn.serial = Serial.init();
    krn.logger = Logger.init(.DEBUG);

    const boot_info: *multiboot.multiboot_info = @ptrFromInt(address);
    krn.boot_info = boot_info;
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
    system.enableWriteProtect();

    irq.register_handler(1, &keyboard.keyboard_interrupt);
    krn.logger.INFO("Keyboard handler added", .{});
    krn.task.initial_task.setup(@intFromPtr(&vmm.initial_page_dir), @intFromPtr(&stack_top));
    irq.register_handler(0, &krn.timer_handler);
    syscalls.initSyscalls();
    _ = krn.kthread_create(&tty_thread, null) catch null;
    const arg1: u32 = 2000;
    _ = krn.kthread_create(&test_thread, &arg1) catch null;
    const arg2: u32 = 3000;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;
    _ = krn.kthread_create(&test_thread, &arg2) catch null;

    _ = krn.kthread_create(&output_thread, null) catch null;
    krn.logger.INFO("TTY thread started", .{});
    while (true) {
        asm volatile ("hlt");
    }
    panic("You shouldn't be here");
}
