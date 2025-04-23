const tsk = @import("../sched/task.zig");
const signal = @import("../sched/signals.zig");
const errors = @import("./error-codes.zig");
const arch = @import("arch");
const krn = @import("../main.zig");

pub const sigval = union {
    int: i32,
    ptr: *anyopaque,
};

const siginfo_fields_union = union {
    pad: [128 - 2 * @sizeOf(c_int) - @sizeOf(c_long)]u8,
    common: struct {
        first: union {
            piduid: struct {
                pid: u32,
                uid: u32,
            },
            timer: struct {
                timerid: i32,
                overrun: i32,
            },
        },
        second: union {
            value: sigval,
            sigchld: struct {
                status: i32,
                utime: isize,
                stime: isize,
            },
        },
    },
    sigfault: struct {
        addr: *allowzero anyopaque,
        addr_lsb: i16,
        first: union {
            addr_bnd: struct {
                lower: *anyopaque,
                upper: *anyopaque,
            },
            pkey: u32,
        },
    },
    sigpoll: struct {
        band: isize,
        fd: i32,
    },
    sigsys: struct {
        call_addr: *anyopaque,
        syscall: i32,
        native_arch: u32,
    },
};

pub const siginfo_t = struct {
    signo: i32,
    errno: i32,
    code: i32,
    fields: siginfo_fields_union,
};

pub const sigset_t = [1024 / 32]u32;

pub const Sigaction = struct {
    pub const handler_fn = *align(1) const fn (i32) callconv(.c) void;
    pub const sigaction_fn = *const fn (i32, *const siginfo_t, ?*anyopaque) callconv(.c) void;

    handler: extern union {
        handler: ?handler_fn,
        sigaction: ?sigaction_fn,
    },
    mask: sigset_t,
    flags: c_uint,
    restorer: ?*const fn () callconv(.c) void = null,
};

pub fn sigaction(_: *arch.Regs, sig: u32, act: ?*Sigaction, oact: ?*Sigaction) i32 {
    krn.logger.INFO("sigaction {d} {any} {any}", .{sig, act, oact});
    return 0;
}
