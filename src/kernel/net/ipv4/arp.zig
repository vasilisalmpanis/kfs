const std = @import("std");
const krn = @import("../../main.zig");

const ArpPacket = extern struct {
    htype: u16, // Ethernet = 1
    ptype: u16, // IPv4 = 0x0800
    hlen: u8,     // MAC address length = 6
    plen: u8,     // IPv4 address length = 4
    oper: u16,  // Request = 1, reply = 2
    sha: [6]u8,   // Sender hardware address
    spa: [4]u8,   // Sender protocol address
    tha: [6]u8,   // Target hardware address
    tpa: [4]u8,   // Target protocol address
};

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
