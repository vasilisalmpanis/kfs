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
const io = @import("arch").io;

extern const stack_top: u32;

fn testp(_: ?*const anyopaque) i32 {
    while (true) {
        // dbg.ps();
        // krn.sleep(2000);
    }
    return 0;
}

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

fn go_userspace() void {
    const userspace = @embedFile("userspace");

    const code = krn.mm.uheap.alloc(
        userspace.len,
        true, true
    ) catch 0;
    const code_ptr: [*]u8 = @ptrFromInt(code);
    @memcpy(code_ptr[0..], userspace[0..]);

    const stack_size: u32 = 4096;
    const stack = krn.mm.uheap.alloc(
        stack_size,
        true, true
    ) catch 0;
    const stack_ptr: [*]u8 = @ptrFromInt(stack);
    @memset(stack_ptr[0..stack_size], 0);

    gdt.tss.esp0 = krn.task.current.regs.esp;

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
        [us] "r" (stack + stack_size),
    );
}

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x2BADB002) {
        system.halt();
    }
    krn.serial = Serial.init();
    krn.logger = Logger.init(.DEBUG);

    const boot_info: *multiboot.MultibootInfo = @ptrFromInt(address + mm.PAGE_OFFSET);
    krn.boot_info = boot_info;
    dbg.initSymbolTable(boot_info);
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
    krn.task.initial_task.stack = @intFromPtr(&stack_top);
    idt.idtInit();
    krn.logger.INFO("IDT initialized", .{});
    system.enableWriteProtect();

    irq.registerHandler(1, &keyboard.keyboardInterrupt);
    krn.logger.INFO("Keyboard handler added", .{});

    irq.registerHandler(0, &krn.timerHandler);
    syscalls.initSyscalls();

    _ = krn.kthreadCreate(&tty_thread, null) catch null;
    _ = krn.kthreadCreate(&testp, null) catch null;
    // _ = krn.kthreadCreate(&testp, null) catch null;
    // _ = krn.kthreadCreate(&testp, null) catch null;
    krn.logger.INFO("TTY thread started", .{});

    krn.logger.INFO("Go usermode", .{});

    go_userspace();
    
    while (true) {
        asm volatile ("hlt");
    }
    @panic("You shouldn't be here");
}
