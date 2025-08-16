const kern = @import("kernel");
const dev = @import("./device.zig");
const Bus = @import("./bus.zig").Bus;


/// The device driver generic type
pub const Driver = struct {
    name: []const u8,
    list: kern.list.ListHead,

    // Device initialization and removal.
    probe: *const fn(*Driver, *dev.Device) anyerror!void,
    remove: *const fn(*Driver, *dev.Device) anyerror!void,

    pub fn register(self: *Driver, bus: *Bus) void {
        bus.drivers_mutex.lock();
        if (bus.drivers) |head| {
            head.list.addTail(&self.list);
        } else {
            bus.drivers = self;
        }
        bus.drivers_mutex.unlock();


        bus.device_mutex.lock();
        defer bus.device_mutex.unlock();
        if (bus.devices) |head| {
            var it = head.list.iterator();
            while (it.next()) |node| {
                const bus_dev: *dev.Device = node.curr.entry(dev.Device, "list");
                bus_dev.lock.lock();
                kern.logger.INFO("probe",.{});
                if (bus_dev.driver == null) {
                    // Match device with driver
                    if (bus.match(self, bus_dev)) {
                        bus_dev.driver = self;
                        // Probe the device
                        self.probe(self, bus_dev) catch {
                            bus_dev.driver = null;
                            bus_dev.lock.unlock();
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
