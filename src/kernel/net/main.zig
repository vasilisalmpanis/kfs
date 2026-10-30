const kernel = @import("../main.zig");
const std = @import("std");
const drivers = @import("drivers");
const ipv4 = @import("./ipv4/main.zig");

pub const intf = @import("./if.zig");
pub const dev = @import("./core/dev.zig");
pub const netbuf = @import("./netbuf.zig");
pub const Netbuf = netbuf.Netbuf;

pub const ETH_ADDR_LEN = 6;
pub const ETH_HEADER_LEN = 14;
pub const ARP_PACKET_LEN = 28;
pub const ETH_MIN_PAYLOAD_LEN = 46;
pub const ARP_FRAME_LEN = ETH_HEADER_LEN + ETH_MIN_PAYLOAD_LEN;


pub const ETH_P_LOOP: u16 	= 0x0060;	// Ethernet Loopback packet
pub const ETH_P_IP: u16 	= 0x0800;	// Internet Protocol packet
pub const ETH_P_ARP: u16 	= 0x0806;	// Address Resolution packet

pub const EthernetHeader = extern struct {
    dest_mac: [ETH_ADDR_LEN]u8,
    src_mac: [ETH_ADDR_LEN]u8,
    eth_type: u16,
};

pub fn init() void {
    ipv4.init();
    netbuf.init() catch |err| {
        kernel.logger.ERROR("netbuf cannot be initialized: {t}", .{err});
    };
}
