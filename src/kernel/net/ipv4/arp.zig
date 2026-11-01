const std = @import("std");
const krn = @import("../../main.zig");

const ARPHRD_ETHER      : u16 = 1; // Ethernet 10Mbps
const ARPHRD_IEEE802    : u16 = 6; // IEEE 802.2 Ethernet/TR/TB

const ArpPacket = extern struct {
    htype: u16, // Ethernet = 1
    ptype: u16, // IPv4 = 0x0800
    hlen: u8,     // MAC address length = 6
    plen: u8,     // IPv4 address length = 4
    oper: u16,  // Request = 1, reply = 2
};

const ArpExtension = extern struct {
    sha: [6]u8,   // Sender hardware address
    spa: [4]u8,   // Sender protocol address
    tha: [6]u8,   // Target hardware address
    tpa: [4]u8,   // Target protocol address
};

const ARP_REQUEST   : u16 = 1;
const ARP_REPLY     : u16 = 2;

fn formatPacket(raw: [*]u8, mymac: [6]u8, myip: [4]u8, target_ip: [4]u8) void {
    @memset(raw[0..krn.net.ARP_FRAME_LEN], 0);
    const eth_frame: *krn.net.EthernetHeader = @ptrCast(@alignCast(raw));
    @memset(eth_frame.h_dest[0..6], 0xFF);
    @memcpy(eth_frame.h_source[0..6], mymac[0..6]);
    eth_frame.h_proto = std.mem.nativeToBig(u16, krn.net.ETH_P_ARP);

    const arp: *ArpPacket = @ptrCast(@alignCast(&raw[krn.net.ETH_HEADER_LEN]));
    arp.htype = std.mem.nativeToBig(u16, 1);          // Ethernet
    arp.ptype = std.mem.nativeToBig(u16, krn.net.ETH_P_IP);
    arp.hlen = 6;
    arp.plen = 4;
    arp.oper = std.mem.nativeToBig(u16, 1);           // ARP request
    @memcpy(arp.sha[0..6], mymac[0..6]);
    @memcpy(arp.spa[0..4], myip[0..4]);
    @memcpy(arp.tpa[0..4], target_ip[0..4]);
}

pub fn reply(
    req: *krn.net.Netbuf,
    arp_packet: *ArpPacket,
    arp_data: *ArpExtension
) !bool {
    const ip_to_check = arp_data.tpa;
    _ = req.dev.lookupIP(ip_to_check) orelse
        return false;

    arp_packet.oper = std.mem.nativeToBig(u16, ARP_REPLY);
    arp_data.tha = arp_data.sha;
    arp_data.sha = req.dev.dev_addr;
    arp_data.tpa = arp_data.spa;
    arp_data.spa = ip_to_check;
    return true;
}

pub fn arpReceive(netbuf: *krn.net.Netbuf) !bool {
    const arp_pkt: *ArpPacket = @ptrCast(
        @alignCast(&netbuf.data[netbuf.pos])
    );
    var arp_ext: *ArpExtension = undefined;
    var source_ip: [4]u8 = @splat(0);
    var target_ip: [4]u8 = @splat(0);
    var source_ha: [6]u8 = @splat(0);
    var target_ha: [6]u8 = @splat(0);
    try netbuf.pull(@sizeOf(ArpPacket));

    if (arp_pkt.hlen != netbuf.dev.addr_len or arp_pkt.plen != 4)
        return false;

    switch (
        std.mem.bigToNative(u16, arp_pkt.htype)
    ) {
        ARPHRD_ETHER => {},
        ARPHRD_IEEE802 => @panic("Not implemented, please handle"),
        else => return false
    }

    switch (
        std.mem.bigToNative(u16, arp_pkt.ptype)
    ) {
        krn.net.ETH_P_IP => {},
        else => {
            krn.logger.WARN("Received weird protocol type", .{});
            return false;
        }
    }

    arp_ext = @ptrCast(
        @alignCast(&netbuf.data[netbuf.pos])
    );
    try netbuf.pull(@sizeOf(ArpExtension));
    source_ip = arp_ext.spa;
    target_ip = arp_ext.tpa;
    source_ha = arp_ext.sha;
    target_ha = arp_ext.tha;

    if (source_ha[0] & 1 != 0 or std.mem.allEqual(u8, &source_ha, 0))
        return false;

    if (!update(netbuf.dev, source_ip, source_ha))
        try put(netbuf.dev, source_ip, source_ha);

    return switch (
        std.mem.bigToNative(u16, arp_pkt.oper)
    ) {
        ARP_REQUEST => try reply(netbuf, arp_pkt, arp_ext),
        ARP_REPLY   => false,
        else        => false
    };
}

var lock = krn.Spinlock.init();

const HashKey = struct {
    intf: *krn.net.dev.NetDevice,
    target_ip: [4]u8,
};
var arp_table: std.AutoHashMap(HashKey, [6]u8) = undefined;

pub fn lookup(dev: *krn.net.dev.NetDevice, ip: [4]u8) ?[6]u8 {
    lock.lock();
    defer lock.unlock();
    const key = HashKey{
        .intf = dev,
        .target_ip = ip,
    };
    return arp_table.get(key);
}

pub fn update(
    dev: *krn.net.dev.NetDevice,
    ip: [4]u8,
    mac: [6]u8
) bool {
    lock.lock();
    defer lock.unlock();
    const key = HashKey{
        .intf = dev,
        .target_ip = ip,
    };
    const entry = arp_table.getPtr(key) orelse
        return false;
    entry.* = mac;
    return true;
}

pub fn put(
    dev: *krn.net.dev.NetDevice,
    ip: [4]u8,
    mac: [6]u8
) !void {
    lock.lock();
    defer lock.unlock();
    const key = HashKey{
        .intf = dev,
        .target_ip = ip,
    };
    try arp_table.put(key, mac);
}

pub fn remove(dev: *krn.net.dev.NetDevice, ip: [4]u8) bool {
    lock.lock();
    defer lock.unlock();
    const key = HashKey{
        .intf = dev,
        .target_ip = ip,
    };
    return arp_table.remove(key);
}

pub fn init() void {
    arp_table = std.AutoHashMap(HashKey, [6]u8).init(
        krn.mm.kernel_allocator.allocator()
    );
}
