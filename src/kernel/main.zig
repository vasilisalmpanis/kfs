const drv = @import("drivers");
const TTY = @import("drivers").tty.TTY;
const kbd = @import("drivers").keyboard;
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
pub const kthreadCreate = @import("./sched/kthread.zig").kthreadCreate;
pub const kthreadStop = @import("./sched/kthread.zig").kthreadStop;
pub const task = @import("./sched/task.zig");
pub const sched = @import("./sched/scheduler.zig");
pub const timerHandler = @import("./time/jiffies.zig").timerHandler;
pub const sleep = @import("./sched/task.zig").sleep;
pub const Mutex = @import("./sched/mutex.zig").Mutex;
pub const goUserspace = @import("./userspace/userspace.zig").goUserspace;
pub const signals = @import("./sched/signals.zig");

pub const getSecondsFromStart = @import("./time/jiffies.zig").getSecondsFromStart;
pub const currentMs = @import("./time/jiffies.zig").currentMs;
pub const jiffies = @import("./time/jiffies.zig");
pub const errors = @import("./syscalls/error-codes.zig");

pub const socket = @import("./net/socket.zig");

pub var keyboard: *kbd.Keyboard = &kbd.keyboard;
pub var pit: PIT = undefined;
pub var serial: Serial = undefined;
pub var logger: Logger = undefined;
pub var boot_info: multiboot.Multiboot = undefined;
pub var scr: screen.Screen = undefined;
pub var cmos: drv.cmos.CMOS = undefined;

pub const proc_mm = @import("./mm/proc_mm.zig");
pub const fs = @import("fs/fs.zig");
pub const examplefs = @import("fs/example/filesystem.zig");

pub const mkdir = @import("./syscalls/mkdir.zig").mkdir;
pub const mount = @import("./syscalls/mount.zig").mount;
