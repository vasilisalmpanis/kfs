const kernel = @import("../../main.zig");
const std = @import("std");
const uif = @import("../if.zig");

pub const IPv4Dev = struct {
    list:       kernel.list.ListHead,
    label:      [uif.IFNAMSIZ]u8,
    ip:         [4]u8,
    broadcast:  [4]u8,
    mask:       u32,

    pub fn new(
        label: []const u8,
        ip: [4]u8,
        mask: u32,
    ) ?*IPv4Dev {
        if (label.len >= uif.IFNAMSIZ)
            return null;
        const ipv4_dev = kernel.mm.kmalloc(IPv4Dev) orelse
            return null;
        ipv4_dev.list.setup();
        ipv4_dev.label = @splat(0);
        @memcpy(ipv4_dev.label[0..label.len], label);
        ipv4_dev.ip = ip;
        ipv4_dev.broadcast = @splat(0);
        ipv4_dev.mask = mask;
        return ipv4_dev;
    }

    pub fn getLabel(self: *const IPv4Dev) []const u8 {
        return std.mem.sliceTo(&self.label, 0);
    }
};

const DEFAULT_MASK: u32 = std.mem.nativeToBig(u32, 0xFFFFFF00);

fn calcBroadcast(ip: [4]u8, mask: u32) [4]u8 {
    return @bitCast(@as(u32, @bitCast(ip)) | ~mask);
}

fn setAddr(
    net_dev: *kernel.net.dev.NetDevice,
    ifa: ?*IPv4Dev,
    label: []const u8,
    ip: [4]u8,
) !void {
    const new_ifa = if (ifa) |old| blk: {
        if (std.mem.eql(u8, &old.ip, &ip))
            return;
        net_dev.delIP(old);
        break :blk old;
    } else IPv4Dev.new(label, ip, 0) orelse
        return kernel.errors.PosixError.ENOBUFS;

    new_ifa.ip = ip;
    new_ifa.mask = DEFAULT_MASK;
    new_ifa.broadcast = @splat(0);
    if (net_dev.flags & uif.IFF_BROADCAST != 0)
        new_ifa.broadcast = calcBroadcast(ip, new_ifa.mask);
    net_dev.addIP(new_ifa);
}

fn putAddr(sin: *kernel.socket.sockaddr_in, ip: [4]u8) void {
    sin.* = .{ .port = 0, .addr = @bitCast(ip) };
}

pub fn isDevinetIoctl(op: u32) bool {
    return switch (op) {
        uif.SIOCGIFADDR,
        uif.SIOCGIFBRDADDR,
        uif.SIOCGIFNETMASK,
        uif.SIOCSIFADDR,
        uif.SIOCSIFBRDADDR,
        uif.SIOCSIFNETMASK => true,
        else => false,
    };
}

pub fn devinetIoctl(op: u32, data: usize) !u32 {
    if (data == 0)
        return kernel.errors.PosixError.EFAULT;
    const ifr: *uif.Ifreq = @ptrFromInt(data);
    const sin: *kernel.socket.sockaddr_in = @ptrCast(@alignCast(&ifr.ifr_ifru.addr));
    const in_addr: [4]u8 = @bitCast(sin.addr);

    switch (op) {
        uif.SIOCSIFADDR,
        uif.SIOCSIFBRDADDR,
        uif.SIOCSIFNETMASK => if (sin.family != kernel.socket.AF_INET)
            return kernel.errors.PosixError.EINVAL,
        else => {},
    }

    const net_dev = kernel.net.dev.getByName(ifr.devName()) orelse
        return kernel.errors.PosixError.ENODEV;

    // Lets call all helpers with locks taken and avoid race conditions
    // all together.
    net_dev.lock.lock();
    defer net_dev.lock.unlock();

    const ifa = net_dev.lookupLabel(ifr.name());

    // SIOCSIFADDR creates the intf ip address. All
    // other ioctl cmds require it to exist. Decouple
    // its creation outside of switch to avoid duplicating
    // calls to lookupLabel in every case.
    if (op == uif.SIOCSIFADDR) {
        try setAddr(net_dev, ifa, ifr.name(), in_addr);
        return 0;
    }
    const found = ifa orelse
        return kernel.errors.PosixError.EADDRNOTAVAIL;

    switch (op) {
        uif.SIOCGIFADDR => putAddr(sin, found.ip),
        uif.SIOCGIFBRDADDR => putAddr(sin, found.broadcast),
        uif.SIOCGIFNETMASK => putAddr(sin, @bitCast(found.mask)),
        uif.SIOCSIFBRDADDR => found.broadcast = in_addr,
        else => return kernel.errors.PosixError.ENOTTY,
    }
    return 0;
}
