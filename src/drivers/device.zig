const kern = @import("kernel");
const drv = @import("./driver.zig");
const bus = @import("./bus.zig");

pub const dev_t = packed struct {
    major: u8,
    minor: u8,

    pub fn eql(self: *dev_t, rhs: *dev_t) bool {
        return self.major == rhs.major and self.minor == rhs.minor;
    }
};

var device_mutex = kern.Mutex.init();

pub const Device = struct {
    name: []const u8,
    bus: *bus.Bus,
    driver: ?*drv.Driver,
    id: dev_t,
    lock: kern.Mutex,
    list: kern.list.ListHead, // Bus list (not global)
    tree: kern.tree.TreeNode, // Global

    pub fn new(name: []u8, _bus: *bus.Bus) !*Device {
        // Think about parent child relationship.
        if (kern.mm.kmalloc(Device)) |dev| {
            if (kern.mm.kmallocSlice(u8,name.len)) |_name| {
                @memcpy(_name[0..name.len],name[0..name.len]);
                dev.name = _name;
                dev.driver = null;
                dev.id = dev_t{ .major = 0, .minor = 0};
                dev.bus = _bus;
                dev.lock = kern.Mutex.init();
                dev.list.setup();
                dev.tree.setup();
                return dev;
            }
        }
        return kern.errors.PosixError.ENOMEM;
    }

    pub fn setup(self: *Device, _name: [] const u8, _bus: *bus.Bus) void {
                self.name = _name;
                self.driver = null;
                self.id = dev_t{ .major = 0, .minor = 0};
                self.bus = _bus;
                self.lock = kern.Mutex.init();
                self.list.setup();
                self.tree.setup();
    }

    pub fn delete(self: *Device) void {
        // Probably mark dev_t as free for other devices.
        device_mutex.lock();
        self.tree.del(); // Needs rethinking.
        device_mutex.unlock();
        kern.mm.kfree(self.name.ptr);
        kern.mm.kfree(self);
    }
};

