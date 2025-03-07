const TTY = @import("drivers").tty.TTY;
const keyboard = @import("drivers").keyboard;
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

pub fn tty_thread() void {
    while (true) {
        if (keyboard.keyboard.get_input()) |input| {
            screen.current_tty.?.input(input);
        }
    }
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
    idt.idt_init();
    krn.logger.INFO("IDT initialized", .{});
    
    irq.register_handler(1, &keyboard.keyboard_interrupt);
    irq.register_handler(0, &krn.sched.timer_handler);
    krn.logger.INFO("Keyboard handler added", .{});
    syscalls.initSyscalls();
    krn.task.initial_task.setup(@intFromPtr(&vmm.initial_page_dir), @intFromPtr(&stack_top));
    _ = krn.kthread_create(&tty_thread);
    while (true) {
        asm volatile ("hlt");
    }
    panic("You shouldn't be here");
}
