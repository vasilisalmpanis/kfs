const dev = @import("../device.zig");
const kernel = @import("kernel");
const bus = @import("./bus.zig");
const bdev = @import("../bdev.zig");

pub const StorageDevice = struct {
    dev: dev.Device,

    pub fn alloc(name: []const u8) ?*StorageDevice {
        if (kernel.mm.kmalloc(StorageDevice)) |new_dev| {
            if (kernel.mm.kmallocSlice(u8, name.len)) |dev_name| {
                @memcpy(dev_name[0..], name[0..]);
                new_dev.dev.setup(dev_name, &bus.storage_bus);
                return new_dev;
            }
        }
        return null;
    }

    pub fn free(self: *StorageDevice) void {
        kernel.mm.kfree(self.dev.name.ptr);
        kernel.mm.kfree(self);
    }

    pub fn register(self: *StorageDevice) !void {
        self.dev.bus.add_dev(&self.dev) catch |err| {
            kernel.logger.ERROR("Failer to add Storage device: {any}", .{err});
        };
    }

    pub fn unregister(self: *StorageDevice) !void {
        _ = self;
        // TODO:
    }
};
