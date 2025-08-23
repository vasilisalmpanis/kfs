const kern = @import("kernel");
const dev = @import("./device.zig");
const Bus = @import("./bus.zig").Bus;
const std = @import("std");


/// The device driver generic type
pub const Driver = struct {
    name: []const u8,
    list: kern.list.ListHead,
    minor_set: std.bit_set.StaticBitSet(256) = std.bit_set.StaticBitSet(256).initEmpty(),
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
                kern.fs.UMode{
                    .usr = 0o6,
                },
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
                        self.probe(self, bus_dev) catch {
                            bus_dev.driver = null;
                            bus_dev.lock.unlock();
                            bus_dev.id.major = 0;
                            continue;
                        };
                        
                        bus_dev.lock.unlock();
                        return;
                    }
                }
                bus_dev.lock.unlock();
            }
        }
        return ;
    }

    pub fn unregister(self: *Driver, bus: *Bus) void {
        if (bus.devices) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                const bus_dev: *dev.Device = node.curr.entry(dev.Device, "list");
                bus_dev.lock.lock();
                if (bus_dev.driver == self) {
                    self.remove(bus_dev);
                }
                // TODO: remove the device from the driver
                bus_dev.unlock.lock();
            }
        }
        if (bus.drivers == self) {
           if (self.list.isEmpty()) {
               bus.drivers = null;
           }
           self.list.del();
        }

    }
};
