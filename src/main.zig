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
const std = @import("std");
const cpu = @import("arch").cpu;

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
    dbg.traceStackTrace(20);
    system.halt();
    while (true) {}
}

pub fn tty_thread(_: ?*const anyopaque) i32 {
    while (krn.task.current.should_stop != true) {
        if (keyboard.keyboard.getInput()) |input| {
            screen.current_tty.?.input(input);
        }
    }
    return 0;
}

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    krn.serial = Serial.init();
    krn.logger = Logger.init(.DEBUG);

    const boot_info: *multiboot.MultibootInfo = @ptrFromInt(address);
    krn.boot_info = boot_info;
    krn.logger.INFO("Boot info {}", .{boot_info});

    gdt.gdtInit();
    krn.logger.INFO("GDT initialized", .{});

    mm.mmInit(boot_info);
    krn.logger.INFO("Memory initialized", .{});

    var scrn: screen.Screen = screen.Screen.init(boot_info);
    screen.current_tty = &scrn.tty[0];
    krn.pit = PIT.init(1000);
    krn.task.initial_task.setup(
        @intFromPtr(&vmm.initial_page_dir),
        @intFromPtr(&stack_top)
    );
    idt.idtInit();
    krn.logger.INFO("IDT initialized", .{});
    system.enableWriteProtect();

    irq.registerHandler(1, &keyboard.keyboardInterrupt);
    krn.logger.INFO("Keyboard handler added", .{});
    irq.registerHandler(0, &krn.timerHandler);
    syscalls.initSyscalls();
    _ = krn.kthreadCreate(&tty_thread, null) catch null;
    krn.logger.INFO("TTY thread started", .{});

    const stack = krn.mm.vheap.alloc(4096, true, true) catch 0;
    const code = krn.mm.vheap.alloc(4096, true, true) catch 0;
    const code_ptr: [*]u8 = @ptrFromInt(code);
    code_ptr[0] = 0xeb;
    code_ptr[1] = 0xfe;
    gdt.tss.esp0 = krn.task.current.regs.esp;

    dbg.printGDT();
    dbg.printTSS();
    krn.logger.INFO("Go usermode", .{});
    asm volatile(
        \\ cli
        \\ mov $((8 * 4) | 3), %%bx
        \\ mov %%bx, %%ds
        \\ mov %%bx, %%es
        \\ mov %%bx, %%fs
        \\ mov %%bx, %%gs
        \\
        \\ push $((8 * 4) | 3)
        \\ push %[us]
        \\ pushf
        \\ pop %%ebx
        \\ or $0x200, %%ebx
        \\ push %%ebx
        \\ push $((8 * 3) | 3)
        \\ push %[uc]
        \\ iret
        \\
        ::
        [uc] "r" (code),
        [us] "r" (stack + 4096),
    );
    while (true) {
        asm volatile ("hlt");
    }
    panic("You shouldn't be here");
}
