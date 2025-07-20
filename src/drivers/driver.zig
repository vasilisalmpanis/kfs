const kern = @import("kernel");
const dev = @import("./device.zig");

var drivers: ?*Driver = null;
var driver_mutex = kern.Mutex.init();

/// The device driver generic type
pub const Driver = struct {
    name: []u8,
    list: kern.list.ListHead,

    // Device initialization and removal.
    probe: *const fn(*Driver, *dev.Device) anyerror!void,
    remove: *const fn(*Driver, *dev.Device) anyerror!void,

    pub fn register(driver: *Driver) void {
        driver_mutex.lock();
        defer driver_mutex.unlock();
        if (drivers) |head| {
            head.list.addTail(&driver.list);
        } else {
            drivers = driver;
        }
    }

    pub fn unregister(driver: *Driver) void {
        driver_mutex.lock();
        defer driver_mutex.unlock();
        if (drivers) |head| {
            if (driver == head) {
                if (head.list.isEmpty()) {
                    head = null;
                } else {
                    head = &head.list.next;
                }
            }
            driver.list.del();
        }
    }
};
