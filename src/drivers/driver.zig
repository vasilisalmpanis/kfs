const kern = @import("kernel");
const dev = @import("./device.zig");
const Bus = @import("./bus.zig").Bus;
const std = @import("std");


/// The device driver generic type
pub const Driver = struct {
    name: [:0]const u8,
    list: kern.list.ListHead,
    minor_set: std.StaticBitSet(256) = std.StaticBitSet(256).initEmpty(),
    minor_mutex: kern.Mutex = kern.Mutex.init(),
    major: u8 = 0,
    fops: ?*kern.fs.FileOps = null,

    // Device initialization and removal.
    probe: *const fn(*Driver, *dev.Device) anyerror!void,
    remove: *const fn(*Driver, *dev.Device) anyerror!void,

    pub fn register(self: *Driver, bus: *Bus) !void {
        bus.drivers_mutex.lock();
        if (bus.drivers) |head| {
            head.list.addTail(&self.list);
        } else {
            bus.drivers = self;
        }

        self.major = dev.dev_t.find_major() catch |err| {
            // remove driver and return error.
            if (bus.drivers == self) {
                bus.drivers = null;
            } else {
            }
            return err;
        };

        if (bus.sysfs_drivers) |d| {
            _ = try d.inode.ops.create(
                d.inode,
                self.name,
                kern.fs.UMode.regular(),
                d
            );
        }

        bus.drivers_mutex.unlock();


        bus.device_mutex.lock();
        defer bus.device_mutex.unlock();
        if (bus.devices) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                const bus_dev: *dev.Device = node.curr.entry(dev.Device, "list");
                bus_dev.lock.lock();
                if (bus_dev.driver == null) {
                    // Match device with driver
                    if (bus.match(self, bus_dev)) {
                        bus_dev.driver = self;
                        // Probe the device
                        bus_dev.id.major = self.major;
                        kern.logger.INFO("Probing dev {s} with driver {s}", .{bus_dev.name, self.name});
                        bus_dev.id.minor = try self.getFreeMinor();
                        kern.logger.INFO("dev {s} added with id {any}", .{bus_dev.name, bus_dev.id});
                        self.probe(self, bus_dev) catch {
                            kern.logger.ERROR("Probe failed", .{});
                            bus_dev.driver = null;
                            bus_dev.lock.unlock();
                            bus_dev.id.major = 0;
                            self.minor_set.unset(bus_dev.id.minor);
                            continue;
                        };
                        bus_dev.lock.unlock();
                    }
                }
                bus_dev.lock.unlock();
            }
        }
        return ;
    }

    pub fn unregister(self: *Driver, bus: *Bus) !void {
        // Remove file from sysfs
        if (bus.sysfs_drivers) |_drivers| {
            const driver_file = try _drivers.inode.ops.lookup(_drivers, self.name);
            if (driver_file.inode.ops.unlink) |unlink| {
                try unlink(_drivers.inode, driver_file);
            }
        }
        if (bus.devices) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                const bus_dev: *dev.Device = node.curr.entry(dev.Device, "list");
                bus_dev.lock.lock();
                if (bus_dev.driver == self) {
                    try self.remove(self, bus_dev);
                }
                bus_dev.driver = null;
                bus_dev.lock.unlock();
            }
        }
        if (bus.drivers == self) {
           if (self.list.isEmpty()) {
               bus.drivers = null;
           }
        }
        self.list.del();
    }

    pub fn getFreeMinor(self: *Driver) !u8 {
        self.minor_mutex.lock();
        defer self.minor_mutex.unlock();

        var it = self.minor_set.iterator(
            .{ .direction = .forward, .kind = .unset }
        );
        if (it.next()) |_i| {
            self.minor_set.set(_i);
            return @intCast(_i);
        }
        return kern.errors.PosixError.ENODEV;
    }
};
