// Debug
pub export const print_screen = @import("debug.zig").print_screen;
pub export const print_serial = @import("debug.zig").print_serial;

// Memory
pub export const kmalloc = @import("memory.zig").kmalloc;
pub export const kfree = @import("memory.zig").kfree;
pub export const vmalloc = @import("memory.zig").vmalloc;
pub export const vfree = @import("memory.zig").vfree;

// Devices

// IRQ
// pub export const registerHandler = @import("kernel").irq.registerHandler;
// pub export const unregisterHandler = @import("kernel").irq.unregisterHandler;

// Kthread
pub export const kthreadCreate = @import("kthread.zig").kthreadCreate;
pub export const kthreadStop = @import("kthread.zig").kthreadStop;

pub const load_module = @import("./loader.zig").load_module;

pub const arch = @import("arch");
pub const kernel = @import("kernel");
pub const debug = @import("debug");
pub const drivers = @import("drivers");
