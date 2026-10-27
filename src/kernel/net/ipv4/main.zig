const kernel = @import("../../main.zig");
const uif = @import("../if.zig");
const dev_ioctl = @import("../core/dev_ioctl.zig");

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
        // No interface has an IPv4 address yet
        uif.SIOCGIFADDR,
        uif.SIOCGIFDSTADDR,
        uif.SIOCGIFBRDADDR,
        uif.SIOCGIFNETMASK => return kernel.errors.PosixError.EADDRNOTAVAIL,
        else => {},
    }
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
