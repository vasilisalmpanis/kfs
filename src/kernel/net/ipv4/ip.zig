const std = @import("std");
const in = @import("main.zig");
const krn = @import("../../main.zig");
const icmp = @import("icmp.zig");

pub const IpHeader = extern struct {
        vers_ihl:   u8 = 0,
        tos:        u8 = 0,
        tot_len:    u16 = 0,
        id:         u16 = 0,
        frag_off:   u16 = 0,
        ttl:        u8 = 0,
        protocol:   u8 = 0,
        check:      u16 = 0,
        saddr:      u32 = 0,
        daddr:      u32 = 0,

    pub fn csum(self: *IpHeader) u16 {
        var sum: u32 = 0;
        const header_len = @as(usize, self.ihl()) * 4;
        const data: [*]const u8 = @ptrCast(self);

        var i: usize = 0;
        while (i < header_len) {
            defer i += 2;
            if (i == @offsetOf(IpHeader, "check"))
                continue;
            sum += (@as(u32, data[i]) << 8) | @as(u32, data[i + 1]);
        }

        while ((sum >> 16) != 0) {
            sum = (sum & 0xFFFF) + (sum >> 16);
        }
        return @truncate(~sum);
    }

    pub fn verifyCsum(self: *IpHeader) bool {
        return self.csum() == std.mem.bigToNative(u16, self.check);
    }

    pub inline fn version(self: *IpHeader) u4 {
        return @truncate(self.vers_ihl >> 4);
    }

    pub inline fn ihl(self: *IpHeader) u4 {
        return @truncate(self.vers_ihl & 0x0f);
    }

    pub fn makeReply(self: *IpHeader) void {
        const source = self.saddr;
        self.saddr = self.daddr;
        self.daddr = source;
        self.ttl = 64;
        self.check = std.mem.nativeToBig(u16, self.csum());
    }
};

pub fn receive(pkt: *krn.net.Netbuf) !bool {
    if (pkt.pos > pkt.data.len or pkt.data.len - pkt.pos < @sizeOf(IpHeader))
        return krn.errors.PosixError.E2BIG;
    const ip_h: *IpHeader = @ptrCast(@alignCast(&pkt.data[pkt.pos]));
    const ihl: u4 = ip_h.ihl();

    if (ihl < 5 or ip_h.version() != 4) {
        krn.logger.INFO("ip.receive(): header is not valid!", .{});
        return false;
    }

    const header_len = @as(usize, ihl) * 4;
    const total_len = std.mem.bigToNative(u16, ip_h.tot_len);
    if (total_len < header_len)
        return false;
    try pkt.pull(header_len);

    if (!ip_h.verifyCsum()) {
        krn.logger.INFO("ip.receive(): CSUM is not valid!", .{});
        return false;
    }
    if (
        ip_h.ttl == 0 or
        std.mem.bigToNative(u16, ip_h.frag_off) & 0xbfff != 0
    ) {
        krn.logger.INFO("ip.receive(): TODO: handle fragmentation", .{});
        return false;
    }

    const dest: [4]u8 = @bitCast(ip_h.daddr);
    const our_ip = pkt.dev.lookupIP(dest) orelse
        return false;
    const source: [4]u8 = @bitCast(ip_h.saddr);

    if (
        source[0] == 0
        or source[0] == 127
        or source[0] >= 224
        or std.mem.eql(u8, &source, &our_ip.broadcast)
    ) {
        krn.logger.INFO(
            "ip.receive(): not correct or local ip: {any}",
            .{source}
        );
        return false;
    }

    if (switch (ip_h.protocol) {
        in.IPPROTO_ICMP    => try icmp.receive(pkt, ip_h),
        else               => blk: {
            krn.logger.INFO(
                "ip.receive(): TODO: implement ip protocol {d}",
                .{ip_h.protocol}
            );
            break :blk false;
        }
    }) {
        ip_h.makeReply();
        return true;
    }
    return false;
}
