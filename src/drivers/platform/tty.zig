const std = @import("std");
const krn = @import("kernel");
const io = @import("arch").io;
const scr = @import("../screen.zig");
const kbd = @import("../kbd.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");

const t = @import("./termios.zig");
const tty = @import("./tty_struct.zig");
pub const TTY = tty.TTY;
pub const ConsoleColors = tty.ConsoleColors;

// tty ioctl
pub const TCGETS: u32 = 0x5401;
pub const TCSETS: u32 = 0x5402;
pub const TCSETSW: u32 = 0x5403;
pub const TCSETSF: u32 = 0x5404;
pub const TCSBRK: u32 = 0x5409;
pub const TCXONC: u32 = 0x540A;
pub const TCFLSH: u32 = 0x540B;
pub const TIOCGPGRP: u32 = 0x540F;
pub const TIOCSPGRP: u32 = 0x5410;
pub const TIOCOUTQ: u32 = 0x5411;
pub const TIOCGWINSZ: u32 = 0x5413;
pub const TIOCSWINSZ: u32 = 0x5414;
pub const TIOCINQ: u32 = 0x541B;
pub const TIOCNOTTY: u32 = 0x5422;
pub const TIOCSCTTY: u32 = 0x540E;
pub const TIOCGSID: u32 = 0x5429;
pub const FIONBIO: u32 = 0x5421;
// VT/KD stubs
pub const VT_OPENQRY: u32 = 0x5600;
pub const VT_GETSTATE: u32 = 0x5603;
pub const VT_ACTIVATE: u32 = 0x5606;
pub const VT_WAITACTIVE: u32 = 0x5607;
pub const KDGETMODE: u32 = 0x4B3B;
pub const KDSETMODE: u32 = 0x4B3A;
pub const KD_TEXT: u32 = 0x00;
pub const KD_GRAPHICS: u32 = 0x01;

// VT state structure for VT_GETSTATE
pub const VtStat = extern struct {
    v_active: u16,    // currently active VT
    v_signal: u16,    // signal to send on release
    v_state: u16,     // bitmask of active VTs
};

// driver
var tty_driver = pdrv.PlatformDriver{
    .driver = drv.Driver{
        .list = undefined,
        .name = "tty",
        .probe = undefined,
        .remove = undefined,
        .fops = &tty_file_ops
    },
    .probe = tty_probe,
    .remove = tty_remove
}
;
var tty_file_ops = krn.fs.FileOps{
    .open = tty_open,
    .close = tty_close,
    .read = tty_read,
    .write = tty_write,
    .lseek = null,
    .readdir = null,
    .ioctl = tty_ioctl
};

// file ops
fn getTTY(file: *krn.fs.File) !*TTY {
    if (file.inode.data.dev) |_d|
        return @ptrCast(@alignCast(_d.data));
    return krn.errors.PosixError.EIO;
}

fn tty_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {
    krn.logger.WARN("TTY file opened\n", .{});
}

fn tty_close(base: *krn.fs.File) void {
    krn.logger.WARN("TTY {s} closed\n", .{base.path.?.dentry.name});
}

fn tty_read(file: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    var _tty = try getTTY(file);
    if (_tty.term.c_lflag.ICANON) {
        while (true) {
            _tty.lock.lock();
            if (_tty.file_buff.hasLine()) {
                defer _tty.lock.unlock();
                return @intCast(_tty.file_buff.readLineInto(buf[0..size]));
            }
            _tty.lock.unlock();
        }
    } else {
        const vmin: u8 = _tty.term.c_cc[t.VMIN];
        const vtime: u8 = _tty.term.c_cc[t.VTIME];
        const timeout_ms: u32 = @as(u32, vtime) * 100; // VTIME is in deciseconds

        const start_time = krn.currentMs();

        while (true) {
            _tty.lock.lock();
            const avail = _tty.file_buff.available();
            if (avail == 0) {
                _tty.lock.unlock();
                if (vmin == 0 or _tty.nonblock)
                    return 0;
                // Check timeout if VTIME is set
                if (vtime > 0) {
                    const elapsed = krn.currentMs() - start_time;
                    if (elapsed >= timeout_ms) {
                        return 0; // Timeout expired
                    }
                }
                continue;
            }
            const to_read = @min(@as(u32, avail), size);
            const n = _tty.file_buff.readInto(buf[0..to_read]);
            _tty.lock.unlock();
            return @intCast(n);
        }
    }
}

fn tty_write(file: *krn.fs.File, buf: [*]const u8, size: u32) !u32 {
    var _tty = try getTTY(file);
    const msg = buf[0..size];
    krn.logger.DEBUG("TTY write {s} |{any}|\n", .{msg, msg});
    var i: u32 = 0;
    while (i < msg.len) : (i += 1) {
        const c = msg[i];
        if (c == '\n' and _tty.term.c_oflag.OPOST and _tty.term.c_oflag.ONLCR) {
            _tty.consume('\r');
            _tty.consume('\n');
        } else {
            _tty.consume(c);
        }
    }
    _tty.render();
    return size;
}

fn tty_ioctl(
    file: *krn.fs.File,
    op: u32,
    data: ?*anyopaque
) !u32 {
    var _tty = try getTTY(file);
    switch (op) {
        TCGETS => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TCGETS\n", .{});
                const user_term: *t.Termios = @ptrCast(@alignCast(p));
                user_term.* = _tty.term;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TCSETS, TCSETSW, TCSETSF => {
            if (data) |p| {
                const new_term: *const t.Termios = @ptrCast(@alignCast(p));
                krn.logger.DEBUG("tty_ioctl TCSETS, TCSETSW, TCSETSF\n", .{});
                _tty.term.printDiff(new_term);
                if (op == TCSETSW or op == TCSETSF) {
                    // wait for output to drain
                    _tty.render();
                }
                if (op == TCSETSF) { // flush input queue
                    _tty.lock.lock();
                    _ = _tty.file_buff.reset();
                    _tty.lock.unlock();
                }
                _tty.term = new_term.*;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TCSBRK => {
            krn.logger.DEBUG("tty_ioctl TCSBRK\n", .{});
            return 0;
        },
        TCXONC => {
            krn.logger.DEBUG("tty_ioctl TCXONC\n", .{});
            return 0;
        },
        TCFLSH => {
            // arg: 0=flush input, 1=flush output, 2=both
            if (data) |p| {
                const arg: u32 = @intFromPtr(p);
                krn.logger.DEBUG("tty_ioctl TCFLSH {}\n", .{arg});
                switch (arg & 3) {
                    0 => {
                        _tty.lock.lock();
                        _ = _tty.file_buff.reset();
                        _tty.lock.unlock();
                    },
                    1 => {},
                    2 => {
                        _tty.lock.lock();
                        _ = _tty.file_buff.reset();
                        _tty.lock.unlock();
                    },
                    else => {},
                }
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCGWINSZ => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCGWINSZ\n", .{});
                const user_winsz: *tty.WinSize = @ptrCast(@alignCast(p));
                user_winsz.* = _tty.winsz;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSWINSZ => {
            if (data) |p| {
                const user_winsz: *const tty.WinSize = @ptrCast(@alignCast(p));
                _tty.winsz = user_winsz.*;
                krn.logger.DEBUG("tty_ioctl TIOCSWINSZ new winsz: {}\n", .{_tty.winsz});
                _tty.sendSigToProcGrp(krn.signals.Signal.SIGWINCH);
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCINQ => {
            if (data) |p| {
                krn.logger.DEBUG(
                    "tty_ioctl TIOCINQ, user gets: {d}\n",
                    .{_tty.file_buff.available()}
                );
                const user_inq: *u32 = @ptrCast(@alignCast(p));
                user_inq.* = @intCast(_tty.file_buff.available());
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCOUTQ => {
            if (data) |p| {
                krn.logger.DEBUG(
                    "tty_ioctl TIOCOUTQ, user gets: {d}\n",
                    .{0}
                );
                const user_outq: *u32 = @ptrCast(@alignCast(p));
                user_outq.* = 0; // TODO: output queue size
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCGPGRP => {
            if (data) |p| {
                krn.logger.DEBUG(
                    "tty_ioctl TIOCGPGRP, user gets: {d}\n",
                    .{_tty.fg_pgid}
                );
                const user_pgid: *i32 = @ptrCast(@alignCast(p));
                user_pgid.* = _tty.fg_pgid;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSPGRP => {
            if (data) |p| {
                const new_pgid: i32 = @as(*i32, @ptrCast(@alignCast(p))).*;
                _tty.fg_pgid = new_pgid;
                krn.logger.DEBUG(
                    "TTY {x} tty_ioctl TIOCSPGRP, new fg_pgid: {d}\n",
                    .{@intFromPtr(_tty), _tty.fg_pgid}
                );
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCGSID => {
            if (data) |p| {
                krn.logger.DEBUG(
                    "tty_ioctl TIOCGSID, user gets {d}\n",
                    .{_tty.session_id}
                );
                const user_sid: *i32 = @ptrCast(@alignCast(p));
                user_sid.* = _tty.session_id;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSCTTY => {
            _tty.is_controlling = true;
            _tty.session_id = @intCast(krn.task.current.pgid);
            _tty.fg_pgid = krn.task.current.pgid;
            krn.logger.DEBUG(
                "tty_ioctl TIOCSCTTY: set fg_pgid to {d} (PID {d})\n",
                .{_tty.fg_pgid, krn.task.current.pid}
            );
            return 0;
        },
        TIOCNOTTY => {
            krn.logger.DEBUG("tty_ioctl TIOCNOTTY\n", .{});
            _tty.is_controlling = false;
            return 0;
        },
        FIONBIO => {
            if (data) |p| {
                const user_nonblock: *i32 = @ptrCast(@alignCast(p));
                _tty.nonblock = (user_nonblock.* != 0);
                krn.logger.DEBUG(
                    "tty_ioctl FIONBIO, set nonblock to {}\n", 
                    .{_tty.nonblock}
                );
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        // VT/KD
        VT_OPENQRY => {
            if (data) |p| {
                var next_vt: i32 = 1;
                const current_vt = _tty.vt_index;
                next_vt = @intCast(@mod(current_vt, 10) + 1);

                krn.logger.DEBUG(
                    "tty_ioctl VT_OPENQRY, user gets {d}\n",
                    .{next_vt}
                );
                const user_vt: *i32 = @ptrCast(@alignCast(p));
                user_vt.* = next_vt;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        VT_GETSTATE => {
            if (data) |p| {
                krn.logger.DEBUG("tty_ioctl VT_GETSTATE\n", .{});
                const vt_stat: *VtStat = @ptrCast(@alignCast(p));

                const current_vt = if (scr.current_tty) |curr|
                    curr.vt_index
                else
                    1;
                vt_stat.v_active = current_vt;
                vt_stat.v_signal = 0;
                vt_stat.v_state = 0x7FE;  // Bits 1-10 set (VTs 1-10 exist)

                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        VT_ACTIVATE => {
            krn.logger.DEBUG("tty_ioctl VT_ACTIVATE\n", .{});
            _tty.vt_active = true;
            return 0;
        },
        VT_WAITACTIVE => {
            krn.logger.DEBUG("tty_ioctl VT_WAITACTIVE\n", .{});
            return 0;
        },
        KDGETMODE => {
            if (data) |p| {
                krn.logger.DEBUG(
                    "tty_ioctl KDGETMODE old kd_mode {d}\n",
                    .{_tty.kd_mode}
                );
                @as(*u32, @ptrCast(@alignCast(p))).* = _tty.kd_mode;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        KDSETMODE => {
            if (data) |p| {
                _tty.kd_mode = @as(*u32, @ptrCast(@alignCast(p))).*;
                krn.logger.DEBUG(
                    "tty_ioctl KDSETMODE new kd_mode: {d}\n",
                    .{_tty.kd_mode}
                );
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        else => return krn.errors.PosixError.EINVAL,
    }
}

// probe / thread / init
fn tty_probe(device: *pdev.PlatformDevice) !void {
    if (device.dev.data == null)
        return krn.errors.PosixError.EIO;
    const cur_tty: *TTY = @ptrCast(@alignCast(device.dev.data));
    cur_tty.clear();
    try cdev.addCdev(&device.dev, krn.fs.UMode.chardev());
}

fn tty_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
    krn.logger.WARN("tty cannot be initialized", .{});
}

pub fn tty_thread(_: ?*const anyopaque) i32 {
    while (krn.task.current.should_stop != true) {
        if (kbd.global_keyboard.getInput()) |input| {
            scr.current_tty.?.input(input);
        }
    }
    return 0;
}

fn addTTYDev(name: []const u8) !void {
    if (pdev.PlatformDevice.alloc(name)) |platform_tty| {
        if (krn.mm.kmalloc(TTY)) |curr_tty| {
            var vt_idx: u16 = 0;
            if (name.len > 3 and std.mem.eql(u8, name[0..3], "tty")) {
                vt_idx = std.fmt.parseInt(u16, name[3..], 10) catch 0;
            }
            curr_tty.* = TTY.init(
                scr.framebuffer.cwidth,
                scr.framebuffer.cheight,
                vt_idx
            );
            if (scr.current_tty == null) {
                scr.current_tty = curr_tty;
            }
            platform_tty.dev.data = @ptrCast(@alignCast(curr_tty));
        } else {
            return krn.errors.PosixError.ENOMEM;
        }
        try platform_tty.register();
        return ;
    } else {
        return krn.errors.PosixError.ENOMEM;
    }
}

pub fn init() void {
    // Create tty1 first so it becomes the current_tty (userspace shells use tty1-tty4)
    addTTYDev("tty") catch |err| {
        krn.logger.ERROR("tty1 not added: {t}", .{err});
        return;
    };
    addTTYDev("tty2") catch return;
    addTTYDev("tty3") catch return;
    addTTYDev("tty4") catch return;
    addTTYDev("tty5") catch return;
    addTTYDev("tty6") catch return;
    addTTYDev("tty7") catch return;
    addTTYDev("tty8") catch return;
    addTTYDev("tty9") catch return;
    addTTYDev("tty10") catch return;
    addTTYDev("tty1") catch return;

    pdrv.platform_register_driver(&tty_driver.driver) catch |err| {
        krn.logger.ERROR("Error registering platform driver: {any}", .{err});
        return ;
    };
    krn.logger.WARN("Driver registered for tty", .{});

    _ = krn.kthreadCreate(&tty_thread, null, "tty_thread") catch null;
    return ;
}

fn switchTTY(ctrl: kbd.CtrlType) void {
    krn.logger.INFO("Switch tty {t}", .{ctrl});
    var buff: [10]u8 = undefined;
    const name = std.fmt.bufPrint(
        buff[0..10],
        "/dev/tty{d}",
        .{@intFromEnum(ctrl) - @intFromEnum(kbd.CtrlType.TTY1) + 1}
    ) catch |err| {
        krn.logger.ERROR("switchTTY: {t}", .{err});
        return;
    };
    const path = krn.fs.path.resolve(name) catch |err| {
        krn.logger.ERROR("switchTTY: {t}", .{err});
        return;
    };
    if (!path.dentry.inode.mode.isChr()) {
        krn.logger.ERROR("switchTTY: not char", .{});
        return ;
    }
    const file = krn.fs.File.new(path) catch |err| {
        krn.logger.ERROR("switchTTY: cannot create file: {t}", .{err});
        return ;
    };
    defer file.ref.unref();
    path.dentry.inode.fops.open(file, path.dentry.inode) catch |err| {
        krn.logger.ERROR("switchTTY: cannot create file: {t}", .{err});
        return ;
    };
    if (path.dentry.inode.data.dev) |_d| {
        const curr_tty: *TTY = @ptrCast(@alignCast(_d.data));
        scr.current_tty = curr_tty;
        scr.current_tty.?.reRenderAll();
    } else {
        krn.logger.ERROR("switchTTY: no tty dev", .{});
        return ;
    }
}
