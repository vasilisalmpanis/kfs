const TTY = @import("drivers").tty.TTY;
const Keyboard = @import("drivers").Keyboard;
const PIT = @import("drivers").pit.PIT;
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
pub const kthread_stop = @import("./sched/kthread.zig").kthread_stop;
pub const task = @import("./sched/task.zig");
pub const sched = @import("./sched/scheduler.zig");
pub const timer_handler = @import("./time/jiffies.zig").timer_handler;
pub const switch_to = @import("./sched/scheduler.zig").switch_to;
pub const sleep = @import("./sched/task.zig").sleep;


pub const get_seconds_from_start = @import("./time/jiffies.zig").get_seconds_from_start;
pub const current_ms = @import("./time/jiffies.zig").current_ms;
pub const jiffies = @import("./time/jiffies.zig");

pub var keyboard: Keyboard = undefined;
pub var pit: PIT = undefined;
pub var serial: Serial = undefined;
pub var logger: Logger = undefined;
pub var boot_info: *multiboot.multiboot_info = undefined;
