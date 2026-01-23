
const std = @import("std");
const kfs = @import("kfs");
const api = kfs.api;
const krn = kfs.kernel;
const drv = kfs.drivers;

const pdev = drv.platform.device;
const pdrv = drv.platform.driver;

pub extern fn print_serial(arr: [*]const u8, size: u32) callconv(.c) void;

var kbd_driver = pdrv.PlatformDriver {
    .driver = drv.driver.Driver {
        .list = undefined,
        .name = "kbd",
        .probe = undefined,
        .remove = undefined,
        .fops = &kbd_file_ops,
        .minor_set = std.bit_set.ArrayBitSet(usize, 256).initEmpty(),
        .minor_mutex = krn.Mutex{
            .locked = std.atomic.Value(bool).init(false),
        },
    },
    .probe = kbd_probe,
    .remove = kbd_remove,
};

var kbd_file_ops = krn.fs.file.FileOps{
    .open = kbd_open,
    .close = kbd_close,
    .read = kbd_read,
    .write = kbd_write,
    .lseek = null,
    .readdir = null,
};

fn kbd_open(_: *krn.fs.file.File, _: *krn.fs.Inode) !void {
}

fn kbd_close(_: *krn.fs.file.File) void {
}

fn kbd_read(file: *krn.fs.file.File, buf: [*]u8, size: usize) !usize {
    var to_read: u32 = size;
    if (file.pos >= 256)
        return 0;
    if (to_read > 256 - file.pos) {
        to_read = 256 - file.pos;
    }
    @memcpy(buf[0..to_read], mod_kbd.buffer[file.pos..file.pos + to_read]);
    file.pos += to_read;
    return to_read;
}

fn kbd_write(_: *krn.fs.file.File, _: [*]const u8, _: usize) !usize {
    return kfs.errors.convert(kfs.errors.PosixError.ENOSYS);
}

fn kbd_probe(device: *pdev.PlatformDevice) !void {
    if (device.dev.data == null)
        return kfs.errors.PosixError.EIO;
    _ = api.addCharacterDevice(
        &device.dev,
        krn.fs.UMode{.usr = 0o6, .grp = 0o6, .other = 0o6}
    );

}

fn kbd_remove(device: *pdev.PlatformDevice) !void {
    _ = api.rmCharacterDevice(device.dev.id);
}

var mod_kbd: *kfs.drivers.Keyboard = undefined;

pub fn keyboardInterrupt() void {
    var scancode: u8 = undefined;
    mod_kbd.sendCommand(0xAD); // Disable keyboard
    defer mod_kbd.sendCommand(0xAE); // Enable keyboard
    if (kfs.arch.io.inb(0x64) & 0x01 != 0x01)
        return ;
    scancode = kfs.arch.io.inb(0x60);
    switch (scancode) {
        0xfa, 0xfe  => return,
        0           => { return; },
        0xff        => { return; },
        else        => {}
    }
    // handle e0 e1
    mod_kbd.saveScancode(scancode);
}

pub fn panic(
    msg: []const u8,
    _: ?*std.builtin.StackTrace,
    _: ?usize
) noreturn {
    api.module_panic(msg.ptr, msg.len);
    while (true) {}
}

var global_platform_dev: ?*kfs.drivers.platform.device.PlatformDevice = null;

export fn _init() linksection(".init") callconv(.c) u32 {
    const dev_name: []const u8 = "kbd";
    if (api.allocPlatformDevice(dev_name.ptr, dev_name.len)) |plt_dev| {
        if (kfs.mm.kmalloc(kfs.drivers.Keyboard)) |kbd_data| {
            kfs.dbg.printf("Loading keyboard module\n", .{});
            kbd_data.* = kfs.drivers.Keyboard{
                .buffer = .{0} ** 256,
                .keymap = kfs.dbg.keymap_us,
                .shift = false,
                .cntl = false,
                .alt = false,
                .caps = false,
                .write_pos = 0,
                .read_pos = 0,
            };
            mod_kbd = kbd_data;
            plt_dev.dev.data = kbd_data;
            var res = api.registerPlatformDevice(plt_dev);
            if (res != 0)
                return @intCast(res);
            global_platform_dev = plt_dev;
            res = api.registerPlatformDriver(&kbd_driver.driver);
            if (res != 0)
                return @intCast(res);
            kfs.api.setKBD(mod_kbd);
            kfs.api.registerHandler(1, keyboardInterrupt);
        }
    }
    return 0;
}


export fn _exit() linksection(".exit") callconv(.c) void {
    kfs.api.restoreKBD();
    _ = kfs.api.unregisterPlatformDriver(&kbd_driver.driver);
    if (global_platform_dev) |plt_dev| {
        _ = kfs.api.unregisterPlatformDevice(plt_dev);
    }
}
