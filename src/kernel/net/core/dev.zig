const kernel = @import("../../main.zig");
const std = @import("std");

pub const ETH_ALEN = 6;

pub const NetDeviceOps = struct {
    xmit: * const fn(*NetDevice, dma_addr: u32, len: u16) anyerror!void,
};

pub const NetDevice = struct {
    // TODO, drivers passes name like eth{d} (format)
    // and based on device index correct name is allocated
    // and we get eth0, eth1, eth2 etc.
    name: [kernel.net.intf.IFNAMSIZ]u8 = @splat(0),
    ifindex: u32 = 0,
    addr_len: u8 = ETH_ALEN,
    dev_addr: [ETH_ALEN]u8 = @splat(0),
    broadcast: [ETH_ALEN]u8 = @splat(0xFF),
    ops: *const NetDeviceOps,
    priv: ?*anyopaque = null,
    lock: kernel.Mutex = kernel.Mutex.init(),
    list: kernel.list.ListHead = kernel.list.ListHead.init(),

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
        return new_dev;
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
