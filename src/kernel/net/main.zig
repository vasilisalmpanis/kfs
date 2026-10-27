const kernel = @import("../main.zig");
const std = @import("std");
const drivers = @import("drivers");
const ipv4 = @import("./ipv4/main.zig");

pub const intf = @import("./if.zig");
pub const dev = @import("./core/dev.zig");

const ETH_ADDR_LEN = 6;
const ETH_HEADER_LEN = 14;
const ARP_PACKET_LEN = 28;
const ETH_MIN_PAYLOAD_LEN = 46;
const ARP_FRAME_LEN = ETH_HEADER_LEN + ETH_MIN_PAYLOAD_LEN;


const ETHERTYPE_ARP: u16 = 0x0806;
const ETHERTYPE_IPV4: u16 = 0x0800;

const ETHhdr = extern struct {
  h_dest: [ETH_ADDR_LEN]u8,
  h_source: [ETH_ADDR_LEN]u8,
  h_proto: u16,
};

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
    @memset(raw[0..ARP_FRAME_LEN], 0);
    const eth_frame: *ETHhdr = @ptrCast(@alignCast(raw));
    @memset(eth_frame.h_dest[0..6], 0xFF);
    @memcpy(eth_frame.h_source[0..6], mymac[0..6]);
    eth_frame.h_proto = std.mem.nativeToBig(u16, ETHERTYPE_ARP);

    const arp: *ArpPacket = @ptrCast(@alignCast(&raw[ETH_HEADER_LEN]));
    arp.htype = std.mem.nativeToBig(u16, 1);          // Ethernet
    arp.ptype = std.mem.nativeToBig(u16, ETHERTYPE_IPV4);
    arp.hlen = 6;
    arp.plen = 4;
    arp.oper = std.mem.nativeToBig(u16, 1);           // ARP request
    @memcpy(arp.sha[0..6], mymac[0..6]);
    @memcpy(arp.spa[0..4], myip[0..4]);
    @memcpy(arp.tpa[0..4], target_ip[0..4]);
}

pub fn init() void {
    ipv4.init();
}

// pub fn init() void {
//     _ = kernel.mkdir("/proc/net", 0o444) catch {
//         @panic("unable to create net folder");
//     };
//     // We want to initialize networking
//     // and assign static IP to our guest
//     // write to dma address
//     // interrupt happens and they understand that packet is transmitted or not
//     const net_dev: *kernel.net.dev.NetDevice = kernel.net.dev.getByIndex(1) orelse
//         return;
//
//     const ethernet_packet = kernel.mm.kmallocArray(u8, ARP_FRAME_LEN) orelse
//         return;
//     const phys = kernel.mm.lookupPhys(@intFromPtr(ethernet_packet)) orelse
//         return;
//     formatPacket(
//         ethernet_packet,
//         net_dev.dev_addr,
//         .{10, 0, 2, 15},
//         .{10, 0, 2, 2},
//     );
//     net_dev.ops.xmit(net_dev,
//         phys,
//         ARP_FRAME_LEN
//     ) catch {};
// }
