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
