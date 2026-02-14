const dev = @import("../device.zig");
const kernel = @import("kernel");
const bus = @import("./bus.zig");

pub const PlatformDevice = struct {
    dev: dev.Device,

    pub fn alloc(name: []const u8) ?*PlatformDevice {
        if (kernel.mm.kmalloc(PlatformDevice)) |new_dev| {
            if (kernel.mm.dupSliceZ(u8, name)) |dev_name| {
                new_dev.dev.setup(dev_name, &bus.platform_bus);
                return new_dev;
            }
        }
        return null;
    }

    pub fn free(self: *PlatformDevice) void {
        kernel.mm.kfree(self.dev.name.ptr);
        kernel.mm.kfree(self);
    }

    pub fn register(self: *PlatformDevice) !void {
        self.dev.bus.add_dev(&self.dev) catch |err| {
            kernel.logger.ERROR("Failer to add Platform device: {any}", .{err});
        };
    }

    pub fn unregister(self: *PlatformDevice) !void {
        try self.dev.bus.remove_dev(&self.dev);
    }
};
