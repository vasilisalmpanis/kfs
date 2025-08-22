const drv = @import("./driver.zig");
const dev = @import("./device.zig");
const kern = @import("kernel");

var buses: ?*Bus = null;
var bus_mutex: kern.Mutex = kern.Mutex.init();
pub var sysfs_bus_dentry: ?*kern.fs.DEntry = null;

pub const Bus = struct {
    name: []const u8,
    list: kern.list.ListHead = kern.list.ListHead.init(),
    drivers: ?*drv.Driver,
    drivers_mutex: kern.Mutex = kern.Mutex.init(),
    devices: ?*dev.Device,
    device_mutex: kern.Mutex = kern.Mutex.init(),
    sysfs_dentry: ?*kern.fs.DEntry = null,
    sysfs_devices: ?*kern.fs.DEntry = null,
    sysfs_drivers: ?*kern.fs.DEntry = null,
    // TODO: callbacks to match driver with device.
    //
    match: *const fn(*drv.Driver, *dev.Device) bool,
    scan: ?*const fn(bus: *Bus) void,

    pub fn register(bus: *Bus) !void {
        bus_mutex.lock();
        defer bus_mutex.unlock();

        if (sysfs_bus_dentry) |d| {
            bus.sysfs_dentry = try d.inode.ops.mkdir(
                d.inode,
                d,
                bus.name,
                kern.fs.UMode{
                    .usr = 0o6,
                }
            );
            if (bus.sysfs_dentry) |_d| {
                bus.sysfs_devices = try _d.inode.ops.mkdir(
                    _d.inode,
                    _d,
                    "devices",
                    kern.fs.UMode{
                        .usr = 0o6,
                    }
                );
                bus.sysfs_drivers = try _d.inode.ops.mkdir(
                    _d.inode,
                    _d,
                    "drivers",
                    kern.fs.UMode{
                        .usr = 0o6,
                    }
                );
            }
        }

        if (buses) |head| {
            head.list.addTail(&bus.list);
        } else {
            buses = bus;
        }
        if (bus.scan) |_scan| _scan(bus);
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

        if (bus.sysfs_devices) |d| {
            _ = try d.inode.ops.create(
                d.inode,
                device.name,
                kern.fs.UMode{
                    .usr = 0o6,
                },
                d
            );
        }

        if (bus.devices) |head| {
            head.list.addTail(&device.list);
        } else {
            bus.devices = device;
        }

        // WARN: Maybe we need to run probe for all drivers
        // present on the bus.
    }
};
