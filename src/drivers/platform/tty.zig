const std = @import("std");
const krn = @import("kernel");
const scr = @import("../screen.zig");
const kbd = @import("../kbd.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");
const serial = @import("./serial.zig");

const t = @import("./termios.zig");
const tty = @import("./tty_struct.zig");
pub const TTY = tty.TTY;

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
// VT stubs
pub const VT_OPENQRY: u32 = 0x5600;
pub const VT_GETMODE: u32 = 0x5601;
pub const VT_SETMODE: u32 = 0x5602;
pub const VT_GETSTATE: u32 = 0x5603;
pub const VT_ACTIVATE: u32 = 0x5606;
pub const VT_WAITACTIVE: u32 = 0x5607;

// KD stubs
pub const KDGETMODE: u32 = 0x4B3B;
pub const KDSETMODE: u32 = 0x4B3A;

pub const KD_TEXT: u32 = 0x00;
pub const KD_GRAPHICS: u32 = 0x01;
pub const KD_TEXT0: u32 = 0x02;	// obsolete
pub const KD_TEXT1: u32 = 0x03;	// obsolete

pub const KDGKBMODE:u32 = 0x4B44; // gets current keyboard mode
pub const KDSKBMODE:u32 = 0x4B45; // sets current keyboard mode
pub const KDGKBENT: u32 = 0x4B46; // gets one entry in translation table
pub const KDSKBENT: u32 = 0x4B47; // sets one entry in translation table
pub const KDGETLED:u32 = 0x4B31;  // return current led state
pub const KDSETLED:u32 = 0x4B32;  // set led state [lights, not flags]

pub const K_HOLE: u16 = 2 << 8 | 0;
pub const K_NOSUCHMAP: u16 = 2 << 8 | 127;


const kbentry = extern struct {
    kb_table: u8,
    kb_index: u8,
    kb_value: u16,
};

const VTMode = extern struct {
    mode: u8 = 0,
    waitv: u8 = 0,
    relsig: i16 = 0,
    acqsig: i16 = 0,
    frsig: i16 = 0,
};

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
    .ioctl = tty_ioctl,
    .poll = tty_poll,
};

const MAX_VTS: usize = 10;

var vt_ttys: [MAX_VTS]?*TTY = [_]?*TTY{null} ** MAX_VTS;

fn registerVT(vt_idx: u16, tty_dev: *TTY) void {
    if (vt_idx == 0 or vt_idx > MAX_VTS)
        return;
    vt_ttys[vt_idx - 1] = tty_dev;
}

fn getVT(vt_idx: u16) ?*TTY {
    if (vt_idx == 0 or vt_idx > MAX_VTS)
        return null;
    return vt_ttys[vt_idx - 1];
}

fn flushInputQueue(_tty: *TTY) void {
    _tty.lock.lock();
    _ = _tty.file_buff.reset();
    _tty.lock.unlock();
}

fn isControllingTTY(file: *krn.fs.File) bool {
    if (file.path) |path|
        return std.mem.eql(u8, path.dentry.name, "tty") or std.mem.eql(u8, path.dentry.name, "tty0");
    return false;
}

// file ops
fn getTTY(file: *krn.fs.File) !*TTY {
    if (isControllingTTY(file)) {
        const ctty_file = krn.task.current.controllingTTY() orelse
            return krn.errors.PosixError.ENXIO;
        if (ctty_file == file)
            return krn.errors.PosixError.ENXIO;
        if (ctty_file.inode.data.dev) |_d| {
            return @ptrCast(@alignCast(_d.data));
        }
        return krn.errors.PosixError.EIO;
    }
    if (file.inode.data.dev) |_d|
        return @ptrCast(@alignCast(_d.data));
    return krn.errors.PosixError.EIO;
}

fn tty_open(file: *krn.fs.File, _: *krn.fs.Inode) !void {
    _ = try getTTY(file);
    if (
        (file.flags & krn.fs.file.O_NOCTTY) == 0
        and krn.task.current.controllingTTY() == null
    ) {
        krn.task.current.setControllingTTY(file);
    }
}

fn tty_close(base: *krn.fs.File) void {
    krn.logger.WARN("TTY {s} closed\n", .{base.path.?.dentry.name});
}

fn tty_read(file: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    var _tty = try getTTY(file);
    if (krn.task.current.pgid != _tty.fg_pgid) {
        _ = krn.kill(
            -@as(i32, @intCast(krn.task.current.pgid)),
            @intFromEnum(krn.signals.Signal.SIGTTIN)
        ) catch {
        };
        return krn.errors.PosixError.EINTR;
    }
    if (_tty.term.c_lflag.ICANON) {
        while (true) {
            _tty.lock.lock();
            if (_tty.file_buff.hasLine()) {
                defer _tty.lock.unlock();
                return @intCast(_tty.file_buff.readLineInto(buf[0..size]));
            }
            _tty.lock.unlock();
            _tty.read_queue.wait(true, 0);
            if (krn.task.current.sighand.hasPending())
                return krn.errors.PosixError.EINTR;
        }
    } else {
        const vmin: u8 = _tty.term.c_cc[t.VMIN];
        const vtime: u8 = _tty.term.c_cc[t.VTIME];
        const timeout_ms: u32 = @as(u32, vtime) * 100; // VTIME is in deciseconds

        const start_time = krn.currentMs();

        while (true) {
            _tty.lock.lock();
            const avail = _tty.file_buff.available();
            if (avail == 0 or avail < vmin) {
                const to_read = @min(avail, size);
                if (to_read == 0)
                    _tty.lock.unlock();
                var n: usize = 0;
                if ((vmin == 0 and timeout_ms == 0) or _tty.nonblock) {
                    if (to_read > 0) {
                        n = _tty.file_buff.readInto(buf[0..to_read]);
                        _tty.lock.unlock();
                    }
                    return @intCast(n);
                }
                var elapsed: usize = 0;
                // Check timeout if VTIME is set
                if (vtime > 0) {
                    elapsed = krn.currentMs() - start_time;
                    if (elapsed >= timeout_ms) {
                        if (to_read > 0) {
                            n = _tty.file_buff.readInto(buf[0..to_read]);
                            _tty.lock.unlock();
                        }
                        return @intCast(n);
                    }
                }
                const to_sleep = timeout_ms -| elapsed;
                if (to_sleep == 0 and timeout_ms != 0) {
                    if (to_read > 0) {
                        n = _tty.file_buff.readInto(buf[0..to_read]);
                        _tty.lock.unlock();
                    }
                    return @intCast(n);
                }
                if (to_read > 0)
                    _tty.lock.unlock();
                _tty.read_queue.wait(true, to_sleep);
                if (krn.task.current.sighand.hasPending())
                    return krn.errors.PosixError.EINTR;
                continue;
            }
            const to_read = @min(avail, size);
            const n = _tty.file_buff.readInto(buf[0..to_read]);
            _tty.lock.unlock();
            return @intCast(n);
        }
    }
}

fn print_raw_input(msg: []const u8) void {
    krn.serial.print("tty_write: |");
    for (msg) |_ch| {
        if (std.ascii.isPrint(_ch)) {
            krn.serial.putchar(_ch);
        } else {
            var buff: [5]u8 = .{0} ** 5;
            const buff_s: []u8 = buff[0..5];
            const res = std.fmt.bufPrint(
                buff_s,
                "\\{d}\\", .{_ch}
            ) catch "";
            krn.serial.print(res);
        }
    }
    krn.serial.print("|\n");
}

fn tty_write(file: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    var _tty = try getTTY(file);
    const msg = buf[0..size];
    // print_raw_input(msg);
    var i: usize = 0;
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

fn kbdGetEntry(entry: *kbentry) u16{
    krn.logger.ERROR("ENTRY {any}\n", .{entry});
    const ptr: *u16 = @ptrCast(&entry.kb_value);
    if (entry.kb_table > 0) {
        ptr.* = K_NOSUCHMAP;
    } else {
        ptr.* = K_HOLE;
    }
    return 0;
}

fn kbd_ioctl(_tty: *TTY, op: u32, data: ?*anyopaque) !u32{
    switch (op) {
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
            var mode: u32 = @intFromPtr(data);
            switch (mode) {
                KD_GRAPHICS,
                KD_TEXT => {},
                KD_TEXT0, KD_TEXT1 => {mode = KD_TEXT;},
                else => return krn.errors.PosixError.EINVAL,
            }
            _tty.kd_mode = mode;
            krn.logger.DEBUG(
                "tty_ioctl KDSETMODE new kd_mode: {d}\n",
                .{_tty.kd_mode}
            );
            return 0;
        },
        KDGKBMODE => {
            return 0;
        },
        KDSKBMODE => {
            return 0;
        },
        KDGKBENT => {
            if (data) |entry| {
                const kbd_entry: *kbentry = @ptrCast(@alignCast(entry));
                return kbdGetEntry(kbd_entry);
            }
            return 0;
        },
        KDSKBENT => {
            return 0;
        },
        KDGETLED => {
            return 0;
        },
        KDSETLED => {
            return 0;
        },
        else => return krn.errors.PosixError.ENOIOCTLCMD,
    }
}

fn tty_ioctl(
    file: *krn.fs.File,
    op: u32,
    data: usize
) !u32 {
    var _tty = try getTTY(file);
    const data_ptr: ?*anyopaque = if (data == 0) null else @ptrFromInt(data);
    if (kbd_ioctl(_tty, op, data_ptr)) |res| {
        return res;
    } else |err| switch (err) {
        krn.errors.PosixError.ENOIOCTLCMD => {},
        else => return err,
    }
    switch (op) {
        TCGETS => {
            if (data_ptr) |p| {
                krn.logger.DEBUG("tty_ioctl TCGETS\n", .{});
                const user_term: *t.Termios = @ptrCast(@alignCast(p));
                user_term.* = _tty.term;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TCSETS, TCSETSW, TCSETSF => {
            if (data_ptr) |p| {
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
            const arg: usize = data;
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
        },
        TIOCGWINSZ => {
            if (data_ptr) |p| {
                krn.logger.DEBUG("tty_ioctl TIOCGWINSZ\n", .{});
                const user_winsz: *tty.WinSize = @ptrCast(@alignCast(p));
                user_winsz.* = _tty.winsz;
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCSWINSZ => {
            if (data_ptr) |p| {
                const user_winsz: *const tty.WinSize = @ptrCast(@alignCast(p));
                _tty.winsz = user_winsz.*;
                krn.logger.DEBUG("tty_ioctl TIOCSWINSZ new winsz: {}\n", .{_tty.winsz});
                _tty.sendSigToProcGrp(krn.signals.Signal.SIGWINCH);
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        TIOCINQ => {
            if (data_ptr) |p| {
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
            if (data_ptr) |p| {
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
            if (data_ptr) |p| {
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
            if (data_ptr) |p| {
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
            if (data_ptr) |p| {
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
            const force = data != 0;
            if (krn.task.current.pid != krn.task.current.sid) {
                return krn.errors.PosixError.EPERM;
            }
            if (
                !force
                and krn.task.current.controllingTTY() != null
                and krn.task.current.controllingTTY().? != file
            ) {
                return krn.errors.PosixError.EPERM;
            }
            if (
                !force
                and _tty.session_id != 0
                and _tty.session_id != krn.task.current.sid
            ) {
                return krn.errors.PosixError.EPERM;
            }
            _tty.is_controlling = true;
            _tty.session_id = @intCast(krn.task.current.sid);
            _tty.fg_pgid = krn.task.current.pgid;
            krn.task.current.setControllingTTY(file);
            krn.logger.DEBUG(
                "tty_ioctl TIOCSCTTY: set fg_pgid to {d} (PID {d})\n",
                .{_tty.fg_pgid, krn.task.current.pid}
            );
            return 0;
        },
        TIOCNOTTY => {
            krn.logger.DEBUG("tty_ioctl TIOCNOTTY\n", .{});
            _tty.is_controlling = false;
            if (
                krn.task.current.controllingTTY() != null
                and krn.task.current.controllingTTY().? == file
            ) {
                krn.task.current.clearControllingTTY();
            }
            return 0;
        },
        FIONBIO => {
            if (data_ptr) |p| {
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
            if (data_ptr) |p| {
                var next_vt: i32 = 1;
                const current_vt = _tty.vt_index;
                next_vt = @intCast(@mod(current_vt, MAX_VTS) + 1);

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
        VT_GETMODE => {
            krn.logger.DEBUG("tty_ioctl VT_GETMODE\n", .{});
            if (data_ptr) |p| {
                const user_vt_mode: *VTMode = @ptrCast(@alignCast(p));
                user_vt_mode.* = VTMode{};
                return 0;
            }
            return krn.errors.PosixError.EINVAL;
        },
        VT_SETMODE => {
            krn.logger.DEBUG("tty_ioctl VT_SETMODE\n", .{});
            return 0;
        },
        VT_GETSTATE => {
            if (data_ptr) |p| {
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
        else => return krn.errors.PosixError.EINVAL,
    }
}

fn tty_poll(
    base: *krn.fs.File,
    pollfd: *krn.poll.PollFd,
    poll_table: ?*krn.poll.PollTable
) !u32 {
    const _tty = try getTTY(base);
    var ready: bool = false;
    if (pollfd.events & krn.poll.POLLOUT != 0) {
        pollfd.revents |= krn.poll.POLLOUT;
        ready = true;
    }
    if (pollfd.events & krn.poll.POLLIN != 0) {
        if (_tty.file_buff.available() > 0) {
            pollfd.revents |= krn.poll.POLLIN;
            ready = true;
        }
    }
    if (ready)
        return 1;
    if (poll_table != null and (pollfd.events & krn.poll.POLLIN != 0))
        try poll_table.?.addNode(&_tty.read_queue);
    return 0;
}

// probe / thread / init
fn tty_probe(device: *pdev.PlatformDevice) !void {
    if (
        device.dev.data == null
        and !std.mem.eql(u8, device.dev.name, "tty")
        and !std.mem.eql(u8, device.dev.name, "tty0")
    )
        return krn.errors.PosixError.EIO;
    if (device.dev.data) |data| {
        const cur_tty: *TTY = @ptrCast(@alignCast(data));
        cur_tty.clear();
    }
    try cdev.addCdev(&device.dev, krn.fs.UMode.chardev(), null);
}

fn tty_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
    krn.logger.WARN("tty cannot be initialized", .{});
}

pub fn tty_serial_thread(arg: ?*const anyopaque) i32 {
    const cur_tty: *TTY = if (arg) |_arg|
        @ptrCast(@alignCast(@constCast(_arg)))
    else
        return 0;
    const data = cur_tty.backend_data orelse
        return 0;
    const ser: *serial.Serial = @ptrCast(@alignCast(data));

    while (krn.task.current.should_stop != true) {
        _ = pollSerialTTYInput(cur_tty);
        ser.wait_queue.wait(false, 0);
    }
    return 0;
}

pub fn tty_kbd_thread(_: ?*const anyopaque) i32 {
    while (krn.task.current.should_stop != true) {
        var did_work = false;
        if (kbd.global_keyboard.getInput()) |input| {
            var filtered: [256]kbd.KeyEvent = undefined;
            var filtered_len: usize = 0;
            for (input) |event| {
                if (event.ctl) {
                    const ctrl: kbd.CtrlType = @enumFromInt(event.val);
                    if (isVTControlKey(ctrl)) {
                        switchTTY(ctrl);
                        continue;
                    }
                }
                filtered[filtered_len] = event;
                filtered_len += 1;
            }
            if (filtered_len > 0 and scr.current_tty != null) {
                scr.current_tty.?.input(filtered[0..filtered_len]);
                did_work = true;
            }
        }
        if (!did_work) {
            kbd.wait_queue.wait(false, 0);
        }
    }
    return 0;
}

fn pollSerialTTYInput(cur_tty: *TTY) bool {
    const data = cur_tty.backend_data orelse
        return false;
    const ser: *serial.Serial = @ptrCast(@alignCast(data));
    var got_input = false;
    var n: usize = 0;
    while (n < 256 and ser.canRead()) {
        cur_tty.inputByte(ser.getchar());
        got_input = true;
        n += 1;
    }
    return got_input;
}

fn serialTTYWriteByte(cur_tty: *TTY, b: u8) void {
    if (cur_tty.backend_data) |data| {
        const ser: *serial.Serial = @ptrCast(@alignCast(data));
        ser.putchar(b);
    }
}

fn isVTControlKey(ctrl: kbd.CtrlType) bool {
    const ctrl_num = @intFromEnum(ctrl);
    return (
        ctrl_num >= @intFromEnum(kbd.CtrlType.TTY1)
        and ctrl_num < (@intFromEnum(kbd.CtrlType.TTY1) + MAX_VTS)
    );
}

fn addTTYDev(name: []const u8) !void {
    if (pdev.PlatformDevice.alloc(name)) |platform_tty| {
        var serial_tty: ?*TTY = null;
        if (std.mem.eql(u8, name, "tty") or
            std.mem.eql(u8, name, "tty0")
            ) {
            try platform_tty.register();
            return;
        }
        const is_serial_tty = (
            name.len > 4
            and std.mem.eql(u8, name[0..4], "ttyS")
        );
        if (krn.mm.kmalloc(TTY)) |curr_tty| {
            if (is_serial_tty) {
                const serial_idx = std.fmt.parseInt(u8, name[4..], 10)
                    catch return krn.errors.PosixError.EINVAL;
                const serial_dev = serial.getByIndex(serial_idx)
                    orelse return krn.errors.PosixError.ENODEV;
                curr_tty.* = try TTY.initSerial();
                curr_tty.setBackendOps(.{
                    .writeByte = serialTTYWriteByte,
                });
                curr_tty.backend_data = @ptrCast(serial_dev);
                serial_tty = curr_tty;
            } else {
                var vt_idx: u16 = 0;
                if (name.len > 3 and std.mem.eql(u8, name[0..3], "tty")) {
                    vt_idx = std.fmt.parseInt(u16, name[3..], 10) catch 0;
                }
                curr_tty.* = try TTY.init(
                    scr.framebuffer.cwidth,
                    scr.framebuffer.cheight,
                    vt_idx
                );
                if (scr.current_tty == null) {
                    scr.current_tty = curr_tty;
                }
                registerVT(vt_idx, curr_tty);
            }
            curr_tty.setup();
            platform_tty.dev.data = @ptrCast(@alignCast(curr_tty));
        } else {
            return krn.errors.PosixError.ENOMEM;
        }
        try platform_tty.register();
        if (is_serial_tty and serial_tty != null) {
            _ = krn.kthreadCreate(
                &tty_serial_thread,
                @ptrCast(serial_tty.?),
                "tty_serial_thread"
            ) catch null;
        }
        return ;
    } else {
        return krn.errors.PosixError.ENOMEM;
    }
}

pub fn init() void {
    addTTYDev("tty") catch {
        krn.logger.ERROR("Failed to register /dev/tty file\n", .{});
    };
    addTTYDev("tty0") catch {
        krn.logger.ERROR("Failed to register /dev/tty0 file\n", .{});
    };
    for (1..MAX_VTS) |vt| {
        var name_buf: [8]u8 = undefined;
        const vt_name = std.fmt.bufPrint(name_buf[0..], "tty{d}", .{vt})
            catch continue;
        addTTYDev(vt_name)
            catch continue;
    }

    for (1..serial.MAX_SERIAL_PORTS, 1..) |_, ser_id| {
        if (serial.getByIndex(ser_id)) |_| {
            var name_buf: [8]u8 = undefined;
            const ser_name = std.fmt.bufPrint(name_buf[0..], "ttyS{d}", .{ser_id})
                catch continue;
            addTTYDev(ser_name)
                catch continue;
        }
    }

    pdrv.platform_register_driver(&tty_driver.driver) catch |err| {
        krn.logger.ERROR("Error registering platform driver: {any}", .{err});
        return ;
    };
    krn.logger.WARN("Driver registered for tty", .{});

    _ = krn.kthreadCreate(&tty_kbd_thread, null, "tty_kbd_thread") catch null;
    return ;
}

fn switchTTY(ctrl: kbd.CtrlType) void {
    krn.logger.INFO("Switch tty {t}", .{ctrl});
    const vt_idx: u16 = @intCast(
        @intFromEnum(ctrl) - @intFromEnum(kbd.CtrlType.TTY1) + 1
    );
    const next_tty = getVT(vt_idx) orelse {
        krn.logger.ERROR("switchTTY: tty{d} not found", .{vt_idx});
        return;
    };
    scr.current_tty = next_tty;
    next_tty.reRenderAll();
}
