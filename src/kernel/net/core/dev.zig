const kernel = @import("../../main.zig");
const std = @import("std");

pub const ETH_ALEN = 6;

const uif = kernel.net.intf;

// On SIOCSIFFLAGS userspace passes back every flag it got from SIOCGIFFLAGS,
// including ones it cannot change, such as link state. These are the flags
// that are stored as passed without any driver action. Flags that need an
// action, like IFF_UP, are set only once that action succeeds.
const IFF_PASSIVE: u32 = uif.IFF_DEBUG | uif.IFF_NOTRAILERS | uif.IFF_NOARP |
    uif.IFF_DYNAMIC | uif.IFF_MULTICAST | uif.IFF_PORTSEL | uif.IFF_AUTOMEDIA;

// Flags that we don't implement yet.
const IFF_UNSUPPORTED: u32 = uif.IFF_PROMISC | uif.IFF_ALLMULTI;

pub const NetDeviceOps = struct {
    up:     * const fn(*NetDevice) anyerror!void,
    xmit:   * const fn(*NetDevice, dma_addr: u32, len: u16) anyerror!void,
};

pub const NetDevice = struct {
    // TODO, drivers passes name like eth{d} (format)
    // and based on device index correct name is allocated
    // and we get eth0, eth1, eth2 etc.
    name: [kernel.net.intf.IFNAMSIZ]u8 = @splat(0),
    ifindex: u32 = 0,
    flags: u32 = 0,
    addr_len: u8 = ETH_ALEN,
    dev_addr: [ETH_ALEN]u8 = @splat(0),
    broadcast: [ETH_ALEN]u8 = @splat(0xFF),
    ops: *const NetDeviceOps,
    priv: ?*anyopaque = null,
    lock: kernel.Mutex = kernel.Mutex.init(),
    list: kernel.list.ListHead = kernel.list.ListHead.init(),
    ip_list: ?*kernel.net.ipv4.IPv4Dev = null,

    pub fn new(
        name: []const u8,
        dev_addr: [ETH_ALEN]u8,
        ops: *const NetDeviceOps,
    ) ?*NetDevice {
        if (name.len > kernel.net.intf.IFNAMSIZ)
            return null;
        const new_dev = kernel.mm.kmalloc(NetDevice) orelse
            return null;
        new_dev.* = NetDevice{
            .ops = ops,
        };
        @memcpy(new_dev.name[0..name.len], name[0..name.len]);
        new_dev.dev_addr = dev_addr;
        new_dev.list.setup();
        new_dev.priv = null;
        new_dev.ip_list = null;
        return new_dev;
    }

    // ip_list helpers below expect self.lock held
    pub fn lookupLabel(
        self: *NetDevice,
        label: []const u8
    ) ?*kernel.net.ipv4.IPv4Dev {
        const head = self.ip_list orelse
            return null;
        var it = head.list.iterator();
        while (it.next()) |node| {
            const ifa = node.curr.entry(kernel.net.ipv4.IPv4Dev, "list");
            if (std.mem.eql(u8, ifa.getLabel(), label))
                return ifa;
        }
        return null;
    }

    pub fn addIP(self: *NetDevice, ifa: *kernel.net.ipv4.IPv4Dev) void {
        if (self.ip_list) |head| {
            head.list.addTail(&ifa.list);
        } else {
            ifa.list.setup();
            self.ip_list = ifa;
        }
    }

    pub fn delIP(self: *NetDevice, ifa: *kernel.net.ipv4.IPv4Dev) void {
        if (self.ip_list == ifa) {
            if (ifa.list.isEmpty()) {
                self.ip_list = null;
            } else {
                self.ip_list = ifa.list.next.?.entry(
                    kernel.net.ipv4.IPv4Dev, "list"
                );
            }
        }
        ifa.list.del();
    }

    pub fn open(self: *NetDevice) !void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.flags & uif.IFF_UP != 0)
            return;
        try self.ops.up(self);
        self.flags |= uif.IFF_UP | uif.IFF_RUNNING;
    }

    pub fn changeFlags(self: *NetDevice, flags: u16) !void {
        self.lock.lock();
        const changed = self.flags ^ flags;
        // TODO: bring device down
        const down = changed & uif.IFF_UP != 0 and flags & uif.IFF_UP == 0;
        if (changed & IFF_UNSUPPORTED != 0 or down) {
            self.lock.unlock();
            return kernel.errors.PosixError.EOPNOTSUPP;
        }
        self.flags = (self.flags & ~IFF_PASSIVE) | (flags & IFF_PASSIVE);
        self.lock.unlock();
        if (changed & uif.IFF_UP != 0)
            return self.open();
    }
};

pub var dev_list: ?*NetDevice = null;
pub var dev_mutex = kernel.Mutex.init();
var next_ifindex: u32 = 1;

pub fn register(dev: *NetDevice) !void {
    dev_mutex.lock();
    defer dev_mutex.unlock();
    dev.ifindex = next_ifindex;
    next_ifindex += 1;
    dev.list.setup();
    if (dev_list) |head| {
        head.list.addTail(&dev.list);
    } else {
        dev_list = dev;
    }
}

pub fn unregister(dev: *NetDevice) void {
    dev.close();
    dev_mutex.lock();
    defer dev_mutex.unlock();
    if (dev_list == dev) {
        if (dev.list.isEmpty()) {
            dev_list = null;
        } else {
            dev_list = dev.list.next.?.entry(NetDevice, "list");
        }
    }
    dev.list.del();
}

pub fn getByName(name: []const u8) ?*NetDevice {
    dev_mutex.lock();
    defer dev_mutex.unlock();
    const head = dev_list orelse
        return null;
    var it = head.list.iterator();
    while (it.next()) |node| {
        const dev = node.curr.entry(NetDevice, "list");
        if (std.mem.eql(u8, std.mem.sliceTo(&dev.name, 0), name))
            return dev;
    }
    return null;
}

pub fn getByIndex(ifindex: u32) ?*NetDevice {
    dev_mutex.lock();
    defer dev_mutex.unlock();
    const head = dev_list orelse
        return null;
    var it = head.list.iterator();
    while (it.next()) |node| {
        const dev = node.curr.entry(NetDevice, "list");
        if (dev.ifindex == ifindex)
            return dev;
    }
    return null;
}
