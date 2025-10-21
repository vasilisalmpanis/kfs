const drv = @import("drivers");
const krn = @import("kernel");
const dbg = @import("debug");

pub fn init() void {
    krn.logger.INFO("Modules API initialized\n", .{});
}

// Memory
pub export fn kheap_alloc(size: u32, contig: bool, user: bool) u32 {
    const addr = krn.mm.kheap.alloc(size, contig, user) catch return 0;
    return addr;
}

// Device

pub export fn registerPlatformDevice(pdev: *drv.platform.PlatformDevice) callconv(.c) i32 {
    pdev.register() catch |err| {
        return krn.errors.toErrno(err);
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

pub export fn addCharacterDevice(device: *drv.device.Device, mode: krn.fs.UMode) i32 {
    drv.cdev.addCdev(device, mode) catch |err| {
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

// pub export fn serial(buff: [*]const u8, size: u32) void {
//     krn.logger.INFO(buff[0..size], .{});
// }
