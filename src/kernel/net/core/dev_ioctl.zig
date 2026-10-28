const kernel = @import("../../main.zig");
const std = @import("std");
const uif = @import("../if.zig");
const dev = @import("./dev.zig");

const ETH_DATA_LEN: i32 = 1500;

pub fn isDevIoctl(op: u32) bool {
    return switch (op) {
        uif.SIOCGIFNAME,
        uif.SIOCGIFCONF,
        uif.SIOCGIFFLAGS,
        uif.SIOCSIFFLAGS,
        uif.SIOCGIFMETRIC,
        uif.SIOCGIFMTU,
        uif.SIOCGIFHWADDR,
        uif.SIOCGIFINDEX,
        uif.SIOCGIFTXQLEN,
        uif.SIOCGIFMAP => true,
        else => false,
    };
}

fn ifconf(data: usize) !u32 {
    if (data == 0)
        return kernel.errors.PosixError.EFAULT;
    const ifc: *uif.Ifconf = @ptrFromInt(data);
    ifc.ifc_len = 0;
    return 0;
}

fn getName(data: usize) !u32 {
    const ifr: *uif.Ifreq = @ptrFromInt(data);
    const index = std.math.cast(u32, ifr.ifr_ifru.ivalue) orelse
        return kernel.errors.PosixError.ENODEV;
    const net_dev = dev.getByIndex(index) orelse
        return kernel.errors.PosixError.ENODEV;
    ifr.ifr_name = net_dev.name;
    return 0;
}

pub fn devIoctl(op: u32, data: usize) !u32 {
    if (data == 0)
        return kernel.errors.PosixError.EFAULT;
    switch (op) {
        uif.SIOCGIFCONF => return ifconf(data),
        uif.SIOCGIFNAME => return getName(data),
        else => {},
    }

    const ifr: *uif.Ifreq = @ptrFromInt(data);
    const net_dev = dev.getByName(ifr.name()) orelse
        return kernel.errors.PosixError.ENODEV;

    switch (op) {
        uif.SIOCGIFFLAGS => ifr.ifr_ifru.flags = @truncate(net_dev.flags),
        uif.SIOCSIFFLAGS => try net_dev.changeFlags(ifr.ifr_ifru.flags),
        uif.SIOCGIFMETRIC => ifr.ifr_ifru.ivalue = 0,
        // TODO: NetDevice has no MTU yet
        uif.SIOCGIFMTU => ifr.ifr_ifru.mtu = ETH_DATA_LEN,
        uif.SIOCGIFHWADDR => {
            ifr.ifr_ifru.addr.sa_family = uif.ARPHRD_ETHER;
            ifr.ifr_ifru.addr.sa_data = @splat(0);
            @memcpy(
                ifr.ifr_ifru.addr.sa_data[0..net_dev.addr_len],
                net_dev.dev_addr[0..net_dev.addr_len]
            );
        },
        uif.SIOCGIFINDEX => ifr.ifr_ifru.ivalue = @intCast(net_dev.ifindex),
        uif.SIOCGIFTXQLEN => ifr.ifr_ifru.ivalue = 0,
        uif.SIOCGIFMAP => ifr.ifr_ifru.map = std.mem.zeroes(uif.Ifmap),
        else => return kernel.errors.PosixError.ENOTTY,
    }
    return 0;
}
