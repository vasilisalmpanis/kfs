
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

const test_s: []const u8 = "Test keyboard";

fn kbd_read(_: *krn.fs.file.File, buf: [*]u8, size: u32) !u32 {
    var len = test_s.len;
    if (size < len)
        len = size;
    @memcpy(buf[0..len], test_s[0..len]);
    return len;
}

fn kbd_write(_: *krn.fs.file.File, _: [*]const u8, _: u32) !u32 {
    return 0;
}

fn kbd_probe(device: *pdev.PlatformDevice) !void {
    const tst: [] const u8 = "test\n";
    print_serial(tst.ptr, tst.len);
    // print_serial(device.dev.name.ptr, device.dev.name.len);
    print_serial(tst.ptr, tst.len);
    _ = api.addCharacterDevice(
        &device.dev,
        krn.fs.UMode{.usr = 0o6, .grp = 0o6, .other = 0o6}
    );
}

fn kbd_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
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

export fn _init() linksection(".init") callconv(.c) u32 {
    const dev_name: []const u8 = "kbd";
    if (api.allocPlatformDevice(dev_name.ptr, dev_name.len)) |plt_dev| {
        if (kfs.mm.kmalloc(kfs.drivers.Keyboard)) |kbd_data| {
            print_serial("alloc", 5);
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
            var res = api.registerPlatformDevice(plt_dev);
            if (res != 0)
                return @intCast(res);
            res = api.registerPlatformDriver(&kbd_driver.driver);
            if (res != 0)
                return @intCast(res);
            mod_kbd = kbd_data;
            plt_dev.dev.data = kbd_data;
            kfs.api.setKBD(mod_kbd);
            kfs.api.registerHandler(1, keyboardInterrupt);
        }
    }
    return 0;
}

export fn _exit() linksection(".exit") callconv(.c) void {
}
