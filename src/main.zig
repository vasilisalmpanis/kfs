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
const modules = @import("modules");

pub fn panic(
    msg: []const u8,
    stack: ?*builtin.StackTrace,
    first_trace_addr: ?usize
) noreturn {
    krn.logger.ERROR(
        "\nPANIC: {s}\nfirst_trace_addr {?x}\nstack: {any}\n",
        .{msg, first_trace_addr, stack}
    );
    dbg.traceStackTrace(20);
    system.halt();
    while (true) {}
}

fn move_root() void {
    _ = krn.mkdir("/ext2", 0) catch {
            dbg.printf("Failed to create ext2 directory\n",.{});
            @panic("Not able to mount root\n");
    };
    var root_mountpoint: ?*krn.fs.Mount = null;
    if (krn.fs.FileSystem.find("ext2")) |fs| {
        root_mountpoint = krn.fs.Mount.mount("/dev/sda", "/ext2", fs) catch |err| {
            krn.logger.ERROR("Failed to mount ext2 filesystem: {t}\n",.{err});
            @panic("Not able to mount\n");
        };
    } else {
            dbg.printf("Unknown filesystem type\n",.{});
    }
    if (krn.fs.FileSystem.find("devfs")) |fs| {
        _ = krn.fs.Mount.mount("devfs", "/ext2/dev", fs) catch |err| {
            dbg.printf("Failed to mount devfs to rootfs: {t}\n",.{err});
            @panic("Not able to mount\n");
        };
    } else {
            dbg.printf("Unknown filesystem type\n",.{});
    }
    if (krn.fs.FileSystem.find("sysfs")) |fs| {
        _ = krn.fs.Mount.mount("sysfs", "/ext2/sys", fs) catch {
            dbg.printf("Failed to mount sysfs to rootfs\n",.{});
            @panic("Not able to mount\n");
        };
    } else {
            dbg.printf("Unknown filesystem type\n",.{});
    }
    if (root_mountpoint) |point| {
        krn.task.initial_task.fs.root = krn.fs.path.Path.init(
            point,
            point.sb.root,
        );
        krn.task.initial_task.fs.pwd = krn.fs.path.Path.init(
            point,
            point.sb.root,
        );
        krn.fs.mount.mountpoints.?.remove();
        krn.fs.mount.mountpoints = point;
    }
}

fn user_thread(_: ?*const anyopaque) i32 {
    while (kernel_ready == false)
        krn.sched.reschedule();

    krn.task.current.mm = krn.task.initial_task.mm;
    krn.task.current.fs = krn.task.initial_task.fs;
    krn.task.current.files = krn.task.initial_task.files;
    krn.userspace.prepareBinary(
        @embedFile("userspace"),
        krn.userspace.argv_init,
        krn.userspace.envp_init,
    ) catch {
        @panic("We cannot go to userspace");
    };
    krn.userspace.goUserspace();
    return 0;
}

var kernel_ready: bool = false;

export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x36d76289) {
        system.halt();
    }

    krn.serial = Serial.init(0x3F8);
    krn.serial.setup();
    krn.logger = Logger.init(.DEBUG);
    const boot_info = multiboot.Multiboot.init(address + mm.PAGE_OFFSET);
    krn.boot_info = boot_info;


    gdt.gdtInit();
    mm.mmInit(&krn.boot_info);
    dbg.initSymbolTable(&krn.boot_info);
    krn.logger.INFO("GDT initialized", .{});
    krn.logger.INFO("Memory initialized", .{});

    screen.initScreen(&krn.scr, &krn.boot_info);
    krn.pit = PIT.init(1000);
    krn.task.initMultitasking();
    idt.idtInit();
    krn.logger.INFO("IDT initialized", .{});

    keyboard.init();

    krn.logger.INFO("Keyboard handler added", .{});
    syscalls.initSyscalls();
    drv.cmos.init();

    // FS
    krn.fs.init();

    // Get PID1
    _ = krn.kthreadCreate(&user_thread, null) catch null;

    // Devices
    drv.init();
    modules.init() catch {
        @panic("Modules file cannot be created\n");
    };
    move_root();
    kernel_ready = true;

    while (true) {
        asm volatile ("hlt");
    }
    @panic("You shouldn't be here");
}
