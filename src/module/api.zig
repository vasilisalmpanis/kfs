const drv = @import("drivers");
const krn = @import("kernel");

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
