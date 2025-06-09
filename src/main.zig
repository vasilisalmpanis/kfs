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

pub fn panic(
    msg: []const u8,
    stack: ?*builtin.StackTrace,
    first_trace_addr: ?usize
) noreturn {
    krn.logger.WARN(
        "\nPANIC: {s}\nfirst_trace_addr {?}\nstack: {?}\n",
        .{msg, first_trace_addr, stack}
    );
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

const MultibootInfo = struct {
    total_size: u32,
    reserved: u32,
    // tag list follows
};

const Tag = struct {
    tag_type: u32,
    size: u32,
    // payload follows
};

const FramebufferTag = struct {
    tag_type: u32,
    size: u32,
    framebuffer_addr1: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
    reserved: u8,
    //reserved1: u8,
    //num_color: u32,
};

fn parseMultibootInfo(addr: u32) ?*FramebufferTag {
    const mbi: *MultibootInfo = @ptrFromInt(addr);
    krn.logger.WARN("MBT {any}\n", .{mbi.*});
    var tag: *Tag = @ptrFromInt(addr + @sizeOf(MultibootInfo));
    while (true) {
        if (tag.tag_type == 8) {
            const tag_addr:u32 = @intFromPtr(tag);
            const fb_info: *FramebufferTag = @ptrFromInt(tag_addr);
            return fb_info;
        }
        const curr: u32 = @intFromPtr(tag);
        var size :u32 = tag.size;
        if (size % 8 != 0) {
            size += (8 - size % 8);
        }
        tag = @ptrFromInt(curr + size);
    }
    return null;
}

fn indexed(fb_info: *FramebufferTag) void {
    const virt: [*]u8 = @ptrFromInt(0xE0000000);
    @memset(
        virt[0..fb_info.framebuffer_width * fb_info.framebuffer_height]
        , 
        200
    );
}

fn argb(fb_info: *FramebufferTag) void {
    const virt: [*]u8 = @ptrFromInt(0xE0000000);
    @memset(
        virt[0..fb_info.framebuffer_width * fb_info.framebuffer_height]
        , 
        200
    );
}

pub extern var initial_page_dir: [1024]u32;
export fn kernel_main(magic: u32, address: u32) noreturn {
    if (magic != 0x36d76289) {
        system.halt();
    }
    krn.serial = Serial.init();
    krn.logger = Logger.init(.WARN);
    krn.logger.WARN("size {d}\n", .{@sizeOf(FramebufferTag)});
    initial_page_dir[1023] = (@intFromPtr(&initial_page_dir) - mm.PAGE_OFFSET) | 0x2 | 0x1;
    const fb_info: *FramebufferTag = if (parseMultibootInfo(address + mm.PAGE_OFFSET)) |info| info else system.halt();
    const pd_idx: u32 = 0xE0000000 >> 22;
//    initial_page_dir[pd_idx] = @as(u32, @truncate(fb_info.framebuffer_addr1)) | 0x83;
    initial_page_dir[pd_idx] = 0xFD000000 | 0x83;
    initial_page_dir[pd_idx + 1] = 0xFD000000 + 0x00400000 | 0x83;
    krn.logger.WARN("address {x}\n",.{fb_info.framebuffer_addr1});
    krn.logger.WARN("info {any}\n",.{fb_info.*});
    switch (fb_info.framebuffer_type) {
        0 => {indexed(fb_info);},
        1 => {argb(fb_info);},
        else => {
            @panic("wrong type");
        },
    }
    while (true) {}
}

//export fn kernel_main(magic: u32, address: u32) noreturn {
//    if (magic != 0x36d76289) {
//        system.halt();
//    }
//    const boot_info: *multiboot.MultibootInfo = @ptrFromInt(address + mm.PAGE_OFFSET);
//    krn.boot_info = boot_info;
//
//    krn.serial = Serial.init();
//    krn.logger = Logger.init(.WARN);
//    dbg.initSymbolTable(boot_info);
//    gdt.gdtInit();
//    krn.logger.INFO("GDT initialized", .{});
//
//    mm.mmInit(boot_info);
//    krn.logger.INFO("Memory initialized", .{});
//
//    screen.initScreen(&krn.scr, boot_info);
//
//    krn.pit = PIT.init(1000);
//    krn.task.initMultitasking();
//    idt.idtInit();
//    krn.logger.INFO("IDT initialized", .{});
//irq.registerHandler(1, &keyboard.keyboardInterrupt);
//    krn.logger.INFO("Keyboard handler added", .{});
//    syscalls.initSyscalls();
//
//    _ = krn.kthreadCreate(&tty_thread, null) catch null;
//    krn.logger.INFO("TTY thread started", .{});
//
//    _ = krn.kthreadCreate(&testp, null) catch null;
//    // _ = krn.kthreadCreate(&testp, null) catch null;
//    // _ = krn.kthreadCreate(&testp, null) catch null;
//
//    krn.logger.INFO("Go usermode", .{});
//    krn.goUserspace(@embedFile("userspace"));
//    
//    while (true) {
//        asm volatile ("hlt");
//    }
//    @panic("You shouldn't be here");
//}
