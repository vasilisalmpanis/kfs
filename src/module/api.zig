const drv = @import("drivers");
const krn = @import("kernel");
const dbg = @import("debug");
const std = @import("std");

pub fn init() void {
    krn.logger.INFO("Modules API initialized\n", .{});
}

pub export const error_offset: u16 = @intFromError(krn.errors.PosixError.EPERM);

// Memory
pub export fn kheap_alloc(size: u32, contig: bool, user: bool) u32 {
    const addr = krn.mm.kheap.alloc(size, contig, user) catch return 0;
    return addr;
}

pub export fn kheap_free(addr: u32) void {
    krn.mm.kheap.free(addr);
}

// Drivers

pub export const keymap_us: *const std.EnumMap(drv.keyboard.ScanCode,drv.keyboard.KeymapEntry) = &drv.keyboard.keymap_us;
pub export const keymap_de: *const std.EnumMap(drv.keyboard.ScanCode,drv.keyboard.KeymapEntry) = &drv.keyboard.keymap_de;

// Device

pub export fn registerPlatformDevice(pdev: *drv.platform.PlatformDevice) callconv(.c) i32 {
    pdev.register() catch |err| {
        return krn.errors.toErrno(err);
    };
    return 0;
}
pub export fn unregisterPlatformDevice(pdev: *drv.platform.PlatformDevice) i32 {
    pdev.unregister() catch {
        return 1;
    };
    return 0;
}

pub export fn allocPlatformDevice(name: [*]const u8, name_len: u32) ?*drv.platform.PlatformDevice {
    const name_slice = name[0..name_len];
    return drv.platform.PlatformDevice.alloc(name_slice);
}

pub export fn registerPlatformDriver(driver: *drv.driver.Driver) i32 {
    drv.platform.driver.platform_register_driver(driver) catch |err| {
        return @intFromError(err);
    };
    return 0;
}

pub export fn unregisterPlatformDriver(driver: *drv.driver.Driver) i32 {
    drv.platform.driver.platform_unregister_driver(driver) catch |err| {
        return @intFromError(err);
    };
    return 0;
}

pub export fn addCharacterDevice(device: *drv.device.Device, mode: krn.fs.UMode) i32 {
    drv.cdev.addCdev(device, mode) catch |err| {
        return @intFromError(err);
    };
    return 0;
}

pub export fn rmCharacterDevice(dev: drv.device.dev_t) i32 {
    drv.cdev.rmCdev(dev) catch |err| {
        return @intFromError(err);
    };
    return 0;
}

// Debug

pub export fn printf(buff: [*]const u8, size: u32) void {
    if (krn.screen.current_tty) |t| {
        dbg.print(t, buff[0..size]);
    }
}

pub fn print_serial(arr: [*]const u8, size: u32) callconv(.c) void {
    krn.serial.print(arr[0..size]);
}

// Keyboard

pub export fn setKBD(kbd: *drv.keyboard.Keyboard) void {
    drv.keyboard.global_keyboard = kbd;
}

pub export fn restoreKBD() void {
    drv.keyboard.init();
}

// CMOS

pub export fn setCMOS(cmos: *drv.cmos.CMOS) void {
    krn.cmos = cmos;
}

pub export fn restoreCMOS() void {
    drv.cmos.init();
}

// IRQ
pub export const registerHandler = @import("kernel").irq.registerHandler;
pub export const unregisterHandler = @import("kernel").irq.unregisterHandler;

// Panic
pub export fn module_panic(
    msg: [*]const u8,
    msg_len: u32,
) void {
    @panic(msg[0..msg_len]);
}
