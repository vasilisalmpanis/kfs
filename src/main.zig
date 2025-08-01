const TTY = @import("drivers").tty.TTY;
const keyboard = @import("drivers").keyboard;
const PIT = @import("drivers").pit.PIT;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const screen = @import("drivers").screen;
const dbg = @import("debug");
const drv = @import("drivers");
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

pub fn panic(
    msg: []const u8,
    stack: ?*builtin.StackTrace,
    first_trace_addr: ?usize
) noreturn {
    krn.logger.ERROR(
        "\nPANIC: {s}\nfirst_trace_addr {?x}\nstack: {?}\n",
        .{msg, first_trace_addr, stack}
    );
    dbg.traceStackTrace(20);
    system.halt();
    while (true) {}
}

fn testp(_: ?*const anyopaque) i32 {
    // go_userspace();
    while (true) {
        // dbg.ps();
        // krn.sleep(2000);
    }
    return 0;
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
    if (magic != 0x36d76289) {
        system.halt();
    }

    krn.serial = Serial.init();
    krn.logger = Logger.init(.DEBUG);
    var boot_info: multiboot.Multiboot = multiboot.Multiboot.init(address + mm.PAGE_OFFSET);
    dbg.initSymbolTable(&boot_info);
    gdt.gdtInit();
    krn.logger.INFO("GDT initialized", .{});

    mm.mmInit(&boot_info);
    krn.logger.INFO("Memory initialized", .{});

    screen.initScreen(&krn.scr, &boot_info);

    krn.pit = PIT.init(1000);
    krn.task.initMultitasking();
    idt.idtInit();
    krn.logger.INFO("IDT initialized", .{});

    irq.registerHandler(1, &keyboard.keyboardInterrupt);
    krn.logger.INFO("Keyboard handler added", .{});
    syscalls.initSyscalls();
    drv.cmos.init();

    // FS
    krn.fs.init_cache(krn.mm.kernel_allocator.allocator());
    krn.examplefs.init_example();
    if (krn.fs.FileSystem.find("examplefs")) |fs| {
        const root_mount = krn.fs.Mount.mount("/dev/sda1", "/", fs) catch {
            dbg.printf("Failed to mount root\n",.{});
            @panic("Not able to mount /\n");
        };
        krn.task.initial_task.fs = krn.fs.FSInfo.alloc() catch {
            @panic("Initial task must have a root,pwd\n");
        };
        krn.task.initial_task.fs.root = krn.fs.path.Path.init(
            root_mount,
            root_mount.sb.root
        );
        krn.task.initial_task.fs.pwd = krn.fs.path.Path.init(
            root_mount,
            root_mount.sb.root
        );
        if (krn.fs.TaskFiles.new()) |files| {
            files.map.set(0); // No stdin
            files.map.set(1); // No stdout
            files.map.set(2); // No stderr
            krn.task.initial_task.files = files;
        } else {
            @panic("PID 0 doesn't have TaskFiles struct, OOM\n");
        }
    } else {
            dbg.printf("Unknown filesystem type\n",.{});
    }

    // @import("drivers").pci.init();
    // @import("drivers").ata.ata_init();
    _ = krn.kthreadCreate(&tty_thread, null) catch null;
    krn.logger.INFO("TTY thread started", .{});

    _ = krn.kthreadCreate(&testp, null) catch null;
    // _ = krn.kthreadCreate(&testp, null) catch null;
    // _ = krn.kthreadCreate(&testp, null) catch null;

    krn.logger.INFO("Go usermode", .{});
    krn.goUserspace(@embedFile("userspace"));
    
    while (true) {
        asm volatile ("hlt");
    }
    @panic("You shouldn't be here");
}
