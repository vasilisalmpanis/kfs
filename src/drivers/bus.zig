const drv = @import("./driver.zig");
const dev = @import("./device.zig");
const kern = @import("kernel");

var buses: ?*Bus = null;
var bus_mutex: kern.Mutex = kern.Mutex.init();

pub const Bus = struct {
    name: []const u8,
    list: kern.list.ListHead = kern.list.ListHead.init(),
    drivers: ?*drv.Driver,
    drivers_mutex: kern.Mutex = kern.Mutex.init(),
    devices: ?*dev.Device,
    device_mutex: kern.Mutex = kern.Mutex.init(),
    // TODO: callbacks to match driver with device.
    //
    match: *const fn(*drv.Driver, *dev.Device) bool,

    pub fn register(bus: *Bus) void {
        bus_mutex.lock();
        defer bus_mutex.unlock();
        if (buses) |head| {
            head.list.addTail(&bus.list);
        } else {
            buses = bus;
        }
    }

    pub fn unregister(bus: *Bus) void {
        bus_mutex.lock();
        defer bus_mutex.unlock();
        if (buses) |head| {
            if (head == bus) {
                if (!head.list.isEmpty()) {
                    head = &bus.list.next;
                } else {
                    head = null;
                }
            }
            bus.list.del();
        }
    }

    pub fn add_dev(bus: *Bus, device: *dev.Device) !void {
        bus.device_mutex.lock();
        defer bus.device_mutex.unlock();

        if (bus.devices) |head| {
            head.list.addTail(&device.list);
        } else {
            bus.devices = device;
        }

        // WARN: Maybe we need to run probe for all drivers
        // present on the bus.
    }
};
