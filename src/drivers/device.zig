const kern = @import("kernel");
const drv = @import("./driver.zig");
const bus = @import("./bus.zig");
const std = @import("std");

var dev_t_mutex = kern.Mutex.init();
var major_bitmap = std.bit_set.StaticBitSet(256).initEmpty();

pub const dev_t = packed struct {
    major: u8,
    minor: u8,

    pub fn eql(self: *dev_t, rhs: *dev_t) bool {
        return self.major == rhs.major and self.minor == rhs.minor;
    }

    pub fn find_major() !u8 {
        dev_t_mutex.lock();
        defer dev_t_mutex.unlock();
        for (1..256) |idx| {
            if (!major_bitmap.isSet(idx)) {
                major_bitmap.set(idx);
                return @truncate(idx);
            }
        }
        return kern.errors.PosixError.ENOENT;
    }

    pub fn new(major: u8, bitset: *std.bit_set.ArrayBitSet) !dev_t {
        var res = dev_t{
            .major = major,
            .minor = 0,
        };
        var minor: u8 = 0;
        if (bitset.count() == 256)
            return kern.errors.PosixError.ENOENT;
        for (1..256) |idx| {
            if (!bitset.isSet(idx)) {
                bitset.set(idx);
                minor = idx;
                break;
            }
        }
        res.minor = minor;
        return res;
    }

    pub fn valid(self: *dev_t) bool {
        return self.major != 0 and self.minor != 0;
    }

    pub fn from_u32(val: u32) dev_t {
        return dev_t{
            .major = @truncate((val & 0xFFF00) >> 8),
            .minor = @truncate((val & 0xFF) | ((val >> 12) & 0xFFF00)),
        };
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

