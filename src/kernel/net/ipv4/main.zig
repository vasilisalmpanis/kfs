const kernel = @import("../../main.zig");
const uif = @import("../if.zig");
const dev_ioctl = @import("../core/dev_ioctl.zig");

const devinet = @import("./dev.zig");
pub const IPv4Dev = devinet.IPv4Dev;

const inet_family = kernel.socket.ProtocolFamily {
    .create = inet_create,
};

const inet_protocol_ops = kernel.socket.ProtocolOps{
    .ioctl = inet_ioctl,
};

fn inet_ioctl(
    socket: *kernel.socket.Socket,
    op: u32,
    data: usize
) !u32 {
    _ = socket;
    switch (op) {
        uif.SIOCGIFDSTADDR => return kernel.errors.PosixError.EADDRNOTAVAIL,
        else => {},
    }
    if (devinet.isDevinetIoctl(op))
        return devinet.devinetIoctl(op, data);
    if (dev_ioctl.isDevIoctl(op))
        return dev_ioctl.devIoctl(op, data);
    return kernel.errors.PosixError.ENOTTY;
}

fn inet_create(socket: *kernel.socket.Socket) !void {
    socket.ops = &inet_protocol_ops;
    return;
}

pub fn init() void {
    kernel.socket.net_families[kernel.socket.AF_INET] = &inet_family;
}
