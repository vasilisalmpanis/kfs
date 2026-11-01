const std = @import("std");
const krn = @import("../../main.zig");
const ip = @import("ip.zig");

pub const ICMP_ECHOREPLY:       u8 = 0;	    // Echo Reply
pub const ICMP_DEST_UNREACH:    u8 = 3;	    // Destination Unreachable
pub const ICMP_SOURCE_QUENCH:   u8 = 4;	    // Source Quench
pub const ICMP_REDIRECT:        u8 = 5;	    // Redirect (change route)
pub const ICMP_ECHO:            u8 = 8;	    // Echo Request
pub const ICMP_TIME_EXCEEDED:   u8 = 11;	// Time Exceeded
pub const ICMP_PARAMETERPROB:   u8 = 12;	// Parameter Problem
pub const ICMP_TIMESTAMP:       u8 = 13;	// Timestamp Request
pub const ICMP_TIMESTAMPREPLY:  u8 = 14;	// Timestamp Reply
pub const ICMP_INFO_REQUEST:    u8 = 15;	// Information Request
pub const ICMP_INFO_REPLY:      u8 = 16;	// Information Reply
pub const ICMP_ADDRESS:         u8 = 17;	// Address Mask Request
pub const ICMP_ADDRESSREPLY:    u8 = 18;	// Address Mask Reply

pub const IcmpEchoHeader = extern struct {
    message_type:   u8 = 0,
    code:           u8 = 0,
    check:          u16 = 0,
    identifier:     u16 = 0,
    sequence:       u16 = 0,

    pub fn makeReply(self: *IcmpEchoHeader, message_len: usize) bool {
        if (
            message_len < @sizeOf(IcmpEchoHeader)
            or self.message_type != ICMP_ECHO
            or self.code != 0
        )
            return false;

        if (self.checksum(message_len) != 0)
            return false;

        self.message_type = ICMP_ECHOREPLY;
        self.check = 0;
        self.check = std.mem.nativeToBig(u16, self.checksum(message_len));
        return true;
    }

    pub fn checksum(self: *const IcmpEchoHeader, message_len: usize) u16 {
        const bytes: [*]const u8 = @ptrCast(self);
        const message = bytes[0..message_len];
        var sum: u32 = 0;
        var i: usize = 0;
        while (i + 1 < message.len) {
            defer i += 2;
            sum += (@as(u32, message[i]) << 8) | @as(u32, message[i + 1]);
        }
        if (i < message.len)
            sum += @as(u32, message[i]) << 8;
        while (sum >> 16 != 0) {
            sum = (sum & 0xffff) + (sum >> 16);
        }
        return @truncate(~sum);
    }
};

pub fn receive(pkt: *krn.net.Netbuf, header: *ip.IpHeader) !bool {
    if (header.ihl() != 5)
        return false;

    const total_len = std.mem.bigToNative(u16, header.tot_len);
    const header_len = @as(usize, header.ihl()) * 4;
    if (total_len < header_len)
        return false;
    const icmp_len = total_len - header_len;
    if (
        icmp_len < @sizeOf(IcmpEchoHeader)
        or pkt.pos > pkt.data.len
        or icmp_len > pkt.data.len - pkt.pos
    )
        return krn.errors.PosixError.E2BIG;

    const icmp_start = pkt.pos;
    try pkt.pull(@sizeOf(IcmpEchoHeader));
    const icmp_h: *IcmpEchoHeader = @ptrCast(
        @alignCast(&pkt.data[icmp_start])
    );
    return icmp_h.makeReply(icmp_len);
}
