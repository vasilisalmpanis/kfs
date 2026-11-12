const kernel = @import("../../main.zig");
pub const af_inet = @import("./af_inet.zig");

pub const ip = @import("./ip.zig");
pub const route = @import("./route.zig");

pub const IPPROTO_IP        : u16 = 0;		// Dummy protocol for TCP
pub const IPPROTO_ICMP      : u16 = 1;		// Internet Control Message Protocol
pub const IPPROTO_IGMP      : u16 = 2;		// Internet Group Management Protocol
pub const IPPROTO_IPIP      : u16 = 4;		// IPIP tunnels (older KA9Q tunnels use 94)
pub const IPPROTO_TCP       : u16 = 6;		// Transmission Control Protocol
pub const IPPROTO_EGP       : u16 = 8;		// Exterior Gateway Protocol
pub const IPPROTO_PUP       : u16 = 12;		// PUP protocol
pub const IPPROTO_UDP       : u16 = 17;		// User Datagram Protocol
pub const IPPROTO_IDP       : u16 = 22;		// XNS IDP protocol
pub const IPPROTO_TP        : u16 = 29;		// SO Transport Protocol Class 4
pub const IPPROTO_DCCP      : u16 = 33;		// Datagram Congestion Control Protocol
pub const IPPROTO_IPV6      : u16 = 41;		// IPv6-in-IPv4 tunnelling
pub const IPPROTO_RSVP      : u16 = 46;		// RSVP Protocol
pub const IPPROTO_GRE       : u16 = 47;		// Cisco GRE tunnels (rfc 1701,1702)
pub const IPPROTO_ESP       : u16 = 50;		// Encapsulation Security Payload protocol
pub const IPPROTO_AH        : u16 = 51;		// Authentication Header protocol
pub const IPPROTO_MTP       : u16 = 92;		// Multicast Transport Protocol
pub const IPPROTO_BEETPH    : u16 = 94;		// IP option pseudo header for BEET
pub const IPPROTO_ENCAP     : u16 = 98;		// Encapsulation Header
pub const IPPROTO_PIM       : u16 = 103;    // Protocol Independent Multicast
pub const IPPROTO_COMP      : u16 = 108;    // Compression Header Protocol
pub const IPPROTO_L2TP      : u16 = 115;    // Layer 2 Tunnelling Protocol
pub const IPPROTO_SCTP      : u16 = 132;    // Stream Control Transport Protocol
pub const IPPROTO_UDPLITE   : u16 = 136;	// UDP-Lite (RFC 3828)
pub const IPPROTO_MPLS      : u16 = 137;    // MPLS in IP (RFC 4023)
pub const IPPROTO_ETHERNET  : u16 = 143;	// Ethernet-within-IPv6 Encapsulation
pub const IPPROTO_AGGFRAG   : u16 = 144;	// AGGFRAG in ESP (RFC 9347)
pub const IPPROTO_RAW       : u16 = 255;    // Raw IP packets
pub const IPPROTO_SMC       : u16 = 256;    // Shared Memory Communications
pub const IPPROTO_MPTCP     : u16 = 262;    // Multipath TCP connection

pub const IP_HEADER_LEN: usize = @sizeOf(ip.IpHeader);

pub fn init() void {
    kernel.socket.net_families[kernel.socket.AF_INET] = &af_inet.inet_family;
}
