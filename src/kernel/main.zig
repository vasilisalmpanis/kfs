const TTY = @import("drivers").tty.TTY;
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const multiboot = @import("arch").multiboot;
const screen = @import("drivers").screen;
pub const mm = @import("mm/init.zig");
const dbg = @import("debug");
const builtin = @import("std").builtin;
const idt = @import("arch").idt;
const Serial = @import("drivers").Serial;
const Logger = @import("debug").Logger;
pub const irq = @import("./irq/manage.zig");
pub const exceptions = @import("./irq/exceptions.zig");
pub const syscalls = @import("./irq/syscalls.zig");
pub const list = @import("./utils/list.zig");
pub const kthread_create = @import("./sched/kthread.zig").kthread_create;
pub const task = @import("./sched/task.zig");
pub const sched = @import("./sched/scheduler.zig");
pub const timer_handler = @import("./sched/scheduler.zig").timer_handler;
pub const switch_to = @import("./sched/scheduler.zig").switch_to;


pub var keyboard: Keyboard = undefined;
pub var serial: Serial = undefined;
pub var logger: Logger = undefined;

// pub fn handle_input() void {
//     const input = keyboard.get_input();
//     switch (input[0]) {
//         'R' => system.reboot(),
//         'M' => screen.current_tty.?.move(input[1]),
//         'S' => dbg.TraceStackTrace(10),
//         'C' => screen.current_tty.?.clear(),
//         // 'T' => scrn.switch_tty(input[1]),
//         'I' => {
//             // dbg.print_mmap(boot_info);
//             asm volatile(
//                 \\ xor %eax, %eax
//                 \\ div %eax, %eax
//             );
//             dbg.walkPageTables();
//         },
//         'D' => dbg.run_tests(),
//         else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, true),
//     }
// }
