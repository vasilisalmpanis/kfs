const kernel = @import("../../main.zig");

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
    _ = op;
    _ = data;
    return kernel.errors.PosixError.ENOTTY;
}

fn inet_create(socket: *kernel.socket.Socket) !void {
    socket.ops = &inet_protocol_ops;
    return;
}

pub fn init() void {
    kernel.socket.net_families[kernel.socket.AF_INET] = &inet_family;
}
